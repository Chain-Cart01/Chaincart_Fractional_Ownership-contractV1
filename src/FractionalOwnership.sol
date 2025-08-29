// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {FractionalOwnershipToken} from "./FractionalOwnershipToken.sol";

/**
 * @title FractionalOwnership
 * @author SALAMI SELIM 
 * @notice USD-based fractional ownership with Chainlink price feed
 * @dev Users contribute ETH, tokens minted based on USD value (1 USD = 1 Token) using FractionalOwnershipToken
 */ 
contract FractionalOwnership is ReentrancyGuard {
    //////////////////////////
    /////// ERRORS  /////////
    ////////////////////////
    error FractionalOwnership__ContributionTooSmall();
    error FractionalOwnership__InvalidPriceFeed();
    error FractionalOwnership__InvalidPriceData();

    //////////////////////////
    /////// EVENTS  /////////
    ////////////////////////
    event ContributionMade(address indexed contributor, uint256 ethAmount, uint256 usdValue, uint256 tokensIssued);

    //////////////////////////////////
    /////// STATE VARIABLES  ////////
    ////////////////////////////////
    uint256 public constant MIN_USD_CONTRIBUTION = 1e18; // $1 USD (18 decimals)
    uint256 public constant USD_TO_TOKEN_RATIO = 1e18; // 1 USD = 1 Token (18 decimals)

    AggregatorV3Interface public immutable i_ethUsdPriceFeed;
    FractionalOwnershipToken public immutable i_fractionalOwnershipToken;

    uint256 public s_totalContributions;
    uint256 public s_totalUsdValue;
    uint256 public s_totalTokensIssued;

    mapping(address => uint256) public s_userEthContributions;
    mapping(address => uint256) public s_userUsdContributions;

    /////////////////////////////
    /////// FUNCTIONS  /////////
    ///////////////////////////

    constructor(address _ethUsdPriceFeed) {
        if (_ethUsdPriceFeed == address(0)) {
            revert FractionalOwnership__InvalidPriceFeed();
        }

        i_ethUsdPriceFeed = AggregatorV3Interface(_ethUsdPriceFeed);
        i_fractionalOwnershipToken = new FractionalOwnershipToken();
    }

    /**
     * @notice Contribute ETH and receive tokens based on USD value
     * @dev Converts ETH to USD using Chainlink price feed, then mints tokens at $1 = 1 Token
     */
    function contribute() external payable nonReentrant {
        uint256 ethAmountInUsd = getEthValueInUsd(msg.value);
        
        if (ethAmountInUsd < MIN_USD_CONTRIBUTION) {
            revert FractionalOwnership__ContributionTooSmall();
        }

        uint256 tokensToMint = ethAmountInUsd;

        s_userEthContributions[msg.sender] += msg.value;
        s_userUsdContributions[msg.sender] += ethAmountInUsd;
        s_totalContributions += msg.value;
        s_totalUsdValue += ethAmountInUsd;
        s_totalTokensIssued += tokensToMint;

        i_fractionalOwnershipToken.mint(msg.sender, tokensToMint);

        emit ContributionMade(msg.sender, msg.value, ethAmountInUsd, tokensToMint);
    }

    /**
     * @notice Get ETH value in USD using Chainlink price feed
     * @param ethAmount The amount of ETH to convert (in Wei, 18 decimals)
     * @return usdValue The USD value with 18 decimals
     */
    function getEthValueInUsd(uint256 ethAmount) public view returns (uint256) {
        (uint80 roundId, int256 price, , uint256 timeStamp, uint80 answeredInRound) =
            i_ethUsdPriceFeed.latestRoundData();

        // Validate price feed data
        if (price <= 0 || answeredInRound < roundId || timeStamp == 0) {
            revert FractionalOwnership__InvalidPriceData();
        }
        // Get price feed decimals dynamically
        uint8 decimals = i_ethUsdPriceFeed.decimals();
        uint256 denominator = 10 ** decimals;

        // (ethAmount (18 decimals) * price (decimals)) / 10^decimals = usdValue (18 decimals)
        return (ethAmount * uint256(price)) / denominator;
    }

    /**
     * @notice Get minimum ETH required for $1 USD contribution
     * @return minEthAmount The minimum ETH amount needed (in Wei)
     */
    function getMinEthForUsdContribution() external view returns (uint256) {
        (uint80 roundId, int256 price,, uint256 timeStamp, uint80 answeredInRound) = i_ethUsdPriceFeed.latestRoundData();

        if (price <= 0 || answeredInRound < roundId || timeStamp == 0) {
            revert FractionalOwnership__InvalidPriceData();
        }

        uint8 decimals = i_ethUsdPriceFeed.decimals();
        uint256 denominator = 10 ** decimals;

        // To get $1 USD worth of ETH: $1 (18 decimals) * 10^decimals / price (decimals)
        return (MIN_USD_CONTRIBUTION * denominator) / uint256(price);
    }

    //////////////////////////////////////
    //////   VIEW FUNCTIONS  ///////////
    ////////////////////////////////////

    function getUserEthContribution(address user) external view returns (uint256) {
        return s_userEthContributions[user];
    }

    function getUserUsdContribution(address user) external view returns (uint256) {
        return s_userUsdContributions[user];
    }

    function getUserTokenBalance(address user) external view returns (uint256) {
        return i_fractionalOwnershipToken.balanceOf(user);
    }

    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getTokenAddress() external view returns (address) {
        return address(i_fractionalOwnershipToken);
    }

    function getPriceFeedAddress() external view returns (address) {
        return address(i_ethUsdPriceFeed);
    }

    function calculateTokensForEth(uint256 ethAmount) external view returns (uint256) {
        uint256 usdValue = getEthValueInUsd(ethAmount);
        return usdValue;
    }

    function getEthUsdPrice() external view returns (uint256) {
        (uint80 roundId, int256 price,, uint256 timeStamp, uint80 answeredInRound) = i_ethUsdPriceFeed.latestRoundData();
        if (price <= 0 || answeredInRound < roundId || timeStamp == 0) {
            revert FractionalOwnership__InvalidPriceData();
        }
        return uint256(price);
    }

    function getMinUsdContribution() external pure returns (uint256) {
        return MIN_USD_CONTRIBUTION;
    }

    function getUsdToTokenRatio() external pure returns (uint256) {
        return USD_TO_TOKEN_RATIO;
    }
}