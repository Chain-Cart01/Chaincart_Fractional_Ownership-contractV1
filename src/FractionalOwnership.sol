// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {FractionalOwnershipToken} from "./FractionalOwnershipToken.sol";

/**
 * @title EnhancedFractionalOwnership
 * @author SALAMI SELIM 
 * @notice Multi-token fractional ownership with fiat integration support 
 * @dev Accepts ETH, USDT, USDC and supports fiat on-ramp integration
 */ 
contract FractionalOwnership is ReentrancyGuard, Pausable, AccessControl {
    using SafeERC20 for IERC20;

    //////////////////////////
    /////// ERRORS  /////////
    ////////////////////////
    error ContributionTooSmall();
    error InvalidPriceFeed();
    error InvalidPriceData();
    error TokenNotSupported();
    error InvalidAmount();
    error InvalidAddress();
    error KYCNotCompleted();
    error ContributionLimitExceeded();

    //////////////////////////
    /////// EVENTS  /////////
    ////////////////////////
    event ContributionMade(
        address indexed contributor, 
        address indexed token,
        uint256 amount, 
        uint256 usdValue, 
        uint256 tokensIssued,
        PaymentMethod paymentMethod
    );
    event StablecoinAdded(address indexed token, uint8 decimals);
    event StablecoinRemoved(address indexed token);
    event KYCStatusUpdated(address indexed user, bool status);
    event FiatPaymentProcessed(
        address indexed user,
        uint256 usdAmount,
        string txReference
    );

    //////////////////////////
    /////// ENUMS  //////////
    ////////////////////////
    enum PaymentMethod {
        ETH,
        STABLECOIN,
        FIAT_ONRAMP
    }

    //////////////////////////////////
    /////// STATE VARIABLES  ////////
    ////////////////////////////////
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant FIAT_PROCESSOR_ROLE = keccak256("FIAT_PROCESSOR_ROLE");
    
    uint256 public constant MIN_USD_CONTRIBUTION = 1e18; // $1 USD (18 decimals)
    uint256 public constant USD_TO_TOKEN_RATIO = 1e18; // 1 USD = 1 Token
    uint256 public constant MAX_CONTRIBUTION_PER_USER = 100_000e18; // $100k limit per user

    AggregatorV3Interface public immutable i_ethUsdPriceFeed;
    FractionalOwnershipToken public immutable i_fractionalOwnershipToken;

    // Stablecoin configuration
    struct StablecoinInfo {
        bool isSupported;
        uint8 decimals;
        AggregatorV3Interface priceFeed; // Optional: for non-USD pegged stables
    }

    mapping(address => StablecoinInfo) public supportedStablecoins;
    address[] public stablecoinList;

    // User tracking
    struct UserContribution {
        uint256 totalEthContributed;
        uint256 totalUsdContributed;
        uint256 totalTokensReceived;
        bool isKYCVerified;
        uint256 lastContributionTime;
    }

    mapping(address => UserContribution) public userContributions;

    // Fiat payment tracking
    mapping(string => bool) public processedFiatTransactions;
    
    // Statistics
    uint256 public s_totalContributions;
    uint256 public s_totalUsdValue;
    uint256 public s_totalTokensIssued;
    uint256 public s_uniqueContributors;

    /////////////////////////////
    /////// MODIFIERS  /////////
    ///////////////////////////
    modifier onlyKYCVerified(address user) {
        if (!userContributions[user].isKYCVerified) {
            revert KYCNotCompleted();
        }
        _;
    }

    /////////////////////////////
    /////// FUNCTIONS  /////////
    ///////////////////////////

    constructor(
        address _ethUsdPriceFeed,
        address _usdtAddress,
        address _usdcAddress
    ) {
        if (_ethUsdPriceFeed == address(0)) revert InvalidPriceFeed();

        i_ethUsdPriceFeed = AggregatorV3Interface(_ethUsdPriceFeed);
        i_fractionalOwnershipToken = new FractionalOwnershipToken();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(FIAT_PROCESSOR_ROLE, msg.sender);

        // Initialize USDT support (6 decimals typically)
        if (_usdtAddress != address(0)) {
            supportedStablecoins[_usdtAddress] = StablecoinInfo({
                isSupported: true,
                decimals: 6,
                priceFeed: AggregatorV3Interface(address(0)) // Assume 1:1 USD
            });
            stablecoinList.push(_usdtAddress);
        }

        // Initialize USDC support (6 decimals typically)
        if (_usdcAddress != address(0)) {
            supportedStablecoins[_usdcAddress] = StablecoinInfo({
                isSupported: true,
                decimals: 6,
                priceFeed: AggregatorV3Interface(address(0)) // Assume 1:1 USD
            });
            stablecoinList.push(_usdcAddress);
        }
    }

    /**
     * @notice Contribute ETH and receive tokens
     */
    function contributeETH() 
        external 
        payable 
        nonReentrant 
        whenNotPaused
        onlyKYCVerified(msg.sender) 
    {
        uint256 ethAmountInUsd = getEthValueInUsd(msg.value);
        
        if (ethAmountInUsd < MIN_USD_CONTRIBUTION) {
            revert ContributionTooSmall();
        }

        _processContribution(
            msg.sender,
            address(0), // ETH has no token address
            msg.value,
            ethAmountInUsd,
            PaymentMethod.ETH
        );
    }

    /**
     * @notice Contribute stablecoins (USDT, USDC, etc.)
     * @param token The stablecoin address
     * @param amount The amount to contribute (in token decimals)
     */
    function contributeStablecoin(
        address token,
        uint256 amount
    ) 
        external 
        nonReentrant 
        whenNotPaused
        onlyKYCVerified(msg.sender)
    {
        StablecoinInfo memory stableInfo = supportedStablecoins[token];
        
        if (!stableInfo.isSupported) {
            revert TokenNotSupported();
        }

        // Convert to 18 decimals for USD value
        uint256 usdValue = _normalizeToUsd(amount, stableInfo.decimals);
        
        if (usdValue < MIN_USD_CONTRIBUTION) {
            revert ContributionTooSmall();
        }

        // Transfer stablecoins from user
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        _processContribution(
            msg.sender,
            token,
            amount,
            usdValue,
            PaymentMethod.STABLECOIN
        );
    }

    /**
     * @notice Process fiat payment (called by authorized processor after fiat receipt)
     * @param user The user who made the payment
     * @param usdAmount The USD amount (18 decimals)
     * @param txReference Unique reference from payment processor
     */
    function processFiatPayment(
        address user,
        uint256 usdAmount,
        string calldata txReference
    ) 
        external 
        nonReentrant 
        whenNotPaused
        onlyRole(FIAT_PROCESSOR_ROLE)
        onlyKYCVerified(user)
    {
        if (processedFiatTransactions[txReference]) {
            revert InvalidAmount(); // Already processed
        }

        if (usdAmount < MIN_USD_CONTRIBUTION) {
            revert ContributionTooSmall();
        }

        processedFiatTransactions[txReference] = true;

        _processContribution(
            user,
            address(0),
            0, // No on-chain amount for fiat
            usdAmount,
            PaymentMethod.FIAT_ONRAMP
        );

        emit FiatPaymentProcessed(user, usdAmount, txReference);
    }

    /**
     * @notice Internal function to process contributions
     */
    function _processContribution(
        address user,
        address token,
        uint256 amount,
        uint256 usdValue,
        PaymentMethod paymentMethod
    ) private {
        UserContribution storage contribution = userContributions[user];

        // Check contribution limits
        if (contribution.totalUsdContributed + usdValue > MAX_CONTRIBUTION_PER_USER) {
            revert ContributionLimitExceeded();
        }

        // Track new contributors
        if (contribution.totalUsdContributed == 0) {
            s_uniqueContributors++;
        }

        uint256 tokensToMint = usdValue; // 1:1 ratio

        // Update user stats
        if (paymentMethod == PaymentMethod.ETH) {
            contribution.totalEthContributed += amount;
        }
        contribution.totalUsdContributed += usdValue;
        contribution.totalTokensReceived += tokensToMint;
        contribution.lastContributionTime = block.timestamp;

        // Update global stats
        s_totalContributions += (paymentMethod == PaymentMethod.ETH) ? amount : 0;
        s_totalUsdValue += usdValue;
        s_totalTokensIssued += tokensToMint;

        // Mint tokens
        i_fractionalOwnershipToken.mint(user, tokensToMint);

        emit ContributionMade(user, token, amount, usdValue, tokensToMint, paymentMethod);
    }

    /**
     * @notice Normalize stablecoin amount to 18 decimals
     */
    function _normalizeToUsd(uint256 amount, uint8 decimals) private pure returns (uint256) {
        if (decimals == 18) return amount;
        if (decimals < 18) {
            return amount * 10**(18 - decimals);
        }
        return amount / 10**(decimals - 18);
    }

    /**
     * @notice Get ETH value in USD
     */
    function getEthValueInUsd(uint256 ethAmount) public view returns (uint256) {
        (uint80 roundId, int256 price,, uint256 timeStamp, uint80 answeredInRound) =
            i_ethUsdPriceFeed.latestRoundData();

        if (price <= 0 || answeredInRound < roundId || timeStamp == 0) {
            revert InvalidPriceData();
        }

        uint8 decimals = i_ethUsdPriceFeed.decimals();
        return (ethAmount * uint256(price)) / 10**decimals;
    }

    //////////////////////////////////////
    /////// ADMIN FUNCTIONS  ////////////
    ////////////////////////////////////

    /**
     * @notice Update KYC status for a user
     */
    function updateKYCStatus(address user, bool status) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        userContributions[user].isKYCVerified = status;
        emit KYCStatusUpdated(user, status);
    }

    /**
     * @notice Batch update KYC status
     */
    function batchUpdateKYCStatus(
        address[] calldata users, 
        bool[] calldata statuses
    ) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(users.length == statuses.length, "Length mismatch");
        
        for (uint256 i = 0; i < users.length; i++) {
            userContributions[users[i]].isKYCVerified = statuses[i];
            emit KYCStatusUpdated(users[i], statuses[i]);
        }
    }

    /**
     * @notice Add support for a new stablecoin
     */
    function addStablecoin(
    address token,
    uint8 decimals,
    address priceFeed
) 
    external 
    onlyRole(ADMIN_ROLE) 
{
    if (token == address(0)) {
        revert InvalidAddress();
    }
    
    require(!supportedStablecoins[token].isSupported, "Already supported");
    
    supportedStablecoins[token] = StablecoinInfo({
        isSupported: true,
        decimals: decimals,
        priceFeed: AggregatorV3Interface(priceFeed)
    });
    
    stablecoinList.push(token);
    emit StablecoinAdded(token, decimals);
}

    /**
     * @notice Remove stablecoin support
     */
    function removeStablecoin(address token) 
    external 
    onlyRole(ADMIN_ROLE) 
    {
    if (!supportedStablecoins[token].isSupported) {
        revert TokenNotSupported();
    }
    
    supportedStablecoins[token].isSupported = false;
    emit StablecoinRemoved(token);
   }

    /**
     * @notice Pause contract
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause contract
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Emergency withdrawal of tokens (only in emergency)
     */
    function emergencyWithdraw(
        address token, 
        uint256 amount
    ) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        if (token == address(0)) {
            payable(msg.sender).transfer(amount);
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }
    }

    //////////////////////////////////////
    //////   VIEW FUNCTIONS  ////////////
    ////////////////////////////////////

    function getUserContribution(address user) 
        external 
        view 
        returns (UserContribution memory) 
    {
        return userContributions[user];
    }

    function getUserTokenBalance(address user) external view returns (uint256) {
        return i_fractionalOwnershipToken.balanceOf(user);
    }

    function getContractBalances() 
        external 
        view 
        returns (
            uint256 ethBalance,
            address[] memory tokens,
            uint256[] memory tokenBalances
        ) 
    {
        ethBalance = address(this).balance;
        tokens = stablecoinList;
        tokenBalances = new uint256[](tokens.length);
        
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenBalances[i] = IERC20(tokens[i]).balanceOf(address(this));
        }
    }

    function getTokenAddress() external view returns (address) {
        return address(i_fractionalOwnershipToken);
    }

    function isStablecoinSupported(address token) external view returns (bool) {
        return supportedStablecoins[token].isSupported;
    }

    function getSupportedStablecoins() external view returns (address[] memory) {
        return stablecoinList;
    }

    function calculateTokensForAmount(
        address token,
        uint256 amount
    ) 
        external 
        view 
        returns (uint256) 
    {
        if (token == address(0)) {
            // ETH
            return getEthValueInUsd(amount);
        } else {
            // Stablecoin
            StablecoinInfo memory info = supportedStablecoins[token];
            if (!info.isSupported) return 0;
            return _normalizeToUsd(amount, info.decimals);
        }
    }

    receive() external payable {
        // Allow contract to receive ETH
    }
}