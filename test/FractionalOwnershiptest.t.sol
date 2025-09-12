// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {FractionalOwnership} from "../src/FractionalOwnership.sol";
import {FractionalOwnershipToken} from "../src/FractionalOwnershipToken.sol";
import {MockV3Aggregator} from "./MockV3Aggregator.t.sol";
import {MockERC20} from "./MockV3Aggregator.t.sol";

/**
 * @title FractionalOwnershipTest
 * @author Your Name
 * @notice Comprehensive test suite for FractionalOwnership contract
 * @dev Follows Patrick Collins' testing style with clear organization and descriptions
 */
contract FractionalOwnershipTest is Test {
    // Events
    event ContributionMade(
        address indexed contributor, 
        address indexed token,
        uint256 amount, 
        uint256 usdValue, 
        uint256 tokensIssued,
        FractionalOwnership.PaymentMethod paymentMethod
    );
    event StablecoinAdded(address indexed token, uint8 decimals);
    event StablecoinRemoved(address indexed token);
    event KYCStatusUpdated(address indexed user, bool status);
    event FiatPaymentProcessed(
        address indexed user,
        uint256 usdAmount,
        string txReference
    );

    // Errors
    error ContributionTooSmall();
    error InvalidPriceFeed();
    error InvalidPriceData();
    error TokenNotSupported();
    error InvalidAmount();
    error InvalidAddress();
    error KYCNotCompleted();
    error ContributionLimitExceeded();

    // Contracts
    FractionalOwnership public fractionalOwnership;
    FractionalOwnershipToken public fractionalOwnershipToken;
    
    MockV3Aggregator public ethUsdPriceFeed;
    MockERC20 public usdt;
    MockERC20 public usdc;
    MockERC20 public dai;

    // Constants
    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_PRICE = 2000e8; // $2000 per ETH
    uint256 public constant USDT_DECIMALS = 6;
    uint256 public constant USDC_DECIMALS = 6;
    uint256 public constant DAI_DECIMALS = 18;

    // Test addresses
    address public USER = makeAddr("user");
    address public ADMIN = makeAddr("admin");
    address public FIAT_PROCESSOR = makeAddr("fiatProcessor");
    address public NON_KYC_USER = makeAddr("nonKycUser");

    // Test amounts
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant STARTING_TOKEN_BALANCE = 1000000 * 1e6; // 1M USDT/USDC
    uint256 public constant MIN_CONTRIBUTION_ETH = 0.0005 ether; // ~$1 at $2000/ETH

    //////////////////////
    // Setup Function //
    ////////////////////
    function setUp() public {
        // Deploy mocks
        ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, INITIAL_PRICE);
        usdt = new MockERC20("Tether USD", "USDT", uint8(USDT_DECIMALS));
        usdc = new MockERC20("USD Coin", "USDC", uint8(USDC_DECIMALS));
        dai = new MockERC20("Dai Stablecoin", "DAI", uint8(DAI_DECIMALS));

        // Deploy the main contract
        fractionalOwnership = new FractionalOwnership(
            address(ethUsdPriceFeed),
            address(usdt),
            address(usdc)
        );

        // Get the token address
        fractionalOwnershipToken = FractionalOwnershipToken(fractionalOwnership.getTokenAddress());

        // Setup test accounts with balances
        vm.deal(USER, STARTING_USER_BALANCE);
        vm.deal(NON_KYC_USER, STARTING_USER_BALANCE);
        
        // Mint tokens to users for testing
        usdt.mint(USER, STARTING_TOKEN_BALANCE);
        usdc.mint(USER, STARTING_TOKEN_BALANCE);
        dai.mint(USER, STARTING_TOKEN_BALANCE);

        // Setup roles
        fractionalOwnership.grantRole(fractionalOwnership.ADMIN_ROLE(), ADMIN);
        fractionalOwnership.grantRole(fractionalOwnership.FIAT_PROCESSOR_ROLE(), FIAT_PROCESSOR);

        // Setup KYC for main test user
        fractionalOwnership.updateKYCStatus(USER, true);
    }

    ////////////////////////////
    // Constructor Tests //
    //////////////////////////
    function test_Constructor_Sets_Up_Correctly() public view {
        // Check that price feed is set
        assertEq(address(fractionalOwnership.i_ethUsdPriceFeed()), address(ethUsdPriceFeed));
        
        // Check that token is deployed
        assertTrue(address(fractionalOwnership.i_fractionalOwnershipToken()) != address(0));
        
        // Check that USDT is supported
        assertTrue(fractionalOwnership.isStablecoinSupported(address(usdt)));
        
        // Check that USDC is supported
        assertTrue(fractionalOwnership.isStablecoinSupported(address(usdc)));
        
        // Check constants
        assertEq(fractionalOwnership.MIN_USD_CONTRIBUTION(), 1e18);
        assertEq(fractionalOwnership.USD_TO_TOKEN_RATIO(), 1e18);
        assertEq(fractionalOwnership.MAX_CONTRIBUTION_PER_USER(), 100_000e18);
    }

    function test_Constructor_Reverts_When_PriceFeed_Is_Zero_Address() public {
        vm.expectRevert(InvalidPriceFeed.selector);
        new FractionalOwnership(address(0), address(usdt), address(usdc));
    }

    ////////////////////////////////
    // ETH Contribution Tests //
    //////////////////////////////
    function test_Contribute_ETH_Success() public {
        uint256 ethAmount = MIN_CONTRIBUTION_ETH;
        uint256 expectedUsdValue = fractionalOwnership.getEthValueInUsd(ethAmount);
        uint256 expectedTokens = expectedUsdValue;

        vm.prank(USER);
        
        vm.expectEmit(true, true, false, true);
        emit ContributionMade(
            USER,
            address(0),
            ethAmount,
            expectedUsdValue,
            expectedTokens,
            FractionalOwnership.PaymentMethod.ETH
        );

        fractionalOwnership.contributeETH{value: ethAmount}();

        // Check user contribution data
        FractionalOwnership.UserContribution memory contribution = fractionalOwnership.getUserContribution(USER);
        assertEq(contribution.totalEthContributed, ethAmount);
        assertEq(contribution.totalUsdContributed, expectedUsdValue);
        assertEq(contribution.totalTokensReceived, expectedTokens);

        // Check token balance
        assertEq(fractionalOwnershipToken.balanceOf(USER), expectedTokens);

        // Check global stats
        assertEq(fractionalOwnership.s_totalContributions(), ethAmount);
        assertEq(fractionalOwnership.s_totalUsdValue(), expectedUsdValue);
        assertEq(fractionalOwnership.s_totalTokensIssued(), expectedTokens);
        assertEq(fractionalOwnership.s_uniqueContributors(), 1);
    }

    function test_Contribute_ETH_Reverts_When_Not_KYC_Verified() public {
        vm.prank(NON_KYC_USER);
        vm.expectRevert(KYCNotCompleted.selector);
        fractionalOwnership.contributeETH{value: MIN_CONTRIBUTION_ETH}();
    }

    function test_Contribute_ETH_Reverts_When_Contribution_Too_Small() public {
        uint256 tooSmallAmount = 0.0001 ether; // Much less than $1

        vm.prank(USER);
        vm.expectRevert(ContributionTooSmall.selector);
        fractionalOwnership.contributeETH{value: tooSmallAmount}();
    }

    function test_Contribute_ETH_Reverts_When_Exceeds_Max_Contribution() public {
        // Set ETH price very high to easily exceed max contribution
        ethUsdPriceFeed.updateAnswer(1000000e8); // $1M per ETH

        vm.prank(USER);
        vm.expectRevert(ContributionLimitExceeded.selector);
        fractionalOwnership.contributeETH{value: 1 ether}(); // Would be $1M
    }

    function test_Contribute_ETH_Reverts_When_Contract_Paused() public {
        vm.prank(ADMIN);
        fractionalOwnership.pause();

        vm.prank(USER);
        vm.expectRevert(bytes4(keccak256("EnforcedPause()"))); 
        fractionalOwnership.contributeETH{value: MIN_CONTRIBUTION_ETH}();
    }

    ////////////////////////////////////
    // Stablecoin Contribution Tests //
    //////////////////////////////////
    function test_Contribute_USDT_Success() public {
        uint256 usdtAmount = 10 * 1e6; // $10 USDT (6 decimals)
        uint256 expectedUsdValue = 10e18; // $10 in 18 decimals
        uint256 expectedTokens = expectedUsdValue;

        vm.startPrank(USER);
        usdt.approve(address(fractionalOwnership), usdtAmount);
        
        vm.expectEmit(true, true, false, true);
        emit ContributionMade(
            USER,
            address(usdt),
            usdtAmount,
            expectedUsdValue,
            expectedTokens,
            FractionalOwnership.PaymentMethod.STABLECOIN
        );

        fractionalOwnership.contributeStablecoin(address(usdt), usdtAmount);
        vm.stopPrank();

        // Check balances
        assertEq(usdt.balanceOf(address(fractionalOwnership)), usdtAmount);
        assertEq(fractionalOwnershipToken.balanceOf(USER), expectedTokens);

        // Check user contribution
        FractionalOwnership.UserContribution memory contribution = fractionalOwnership.getUserContribution(USER);
        assertEq(contribution.totalUsdContributed, expectedUsdValue);
        assertEq(contribution.totalTokensReceived, expectedTokens);
    }

    function test_Contribute_USDC_Success() public {
        uint256 usdcAmount = 50 * 1e6; // $50 USDC (6 decimals)
        uint256 expectedUsdValue = 50e18; // $50 in 18 decimals
        uint256 expectedTokens = expectedUsdValue;

        vm.startPrank(USER);
        usdc.approve(address(fractionalOwnership), usdcAmount);
        
        fractionalOwnership.contributeStablecoin(address(usdc), usdcAmount);
        vm.stopPrank();

        // Check balances
        assertEq(usdc.balanceOf(address(fractionalOwnership)), usdcAmount);
        assertEq(fractionalOwnershipToken.balanceOf(USER), expectedTokens);
    }

    function test_Contribute_Stablecoin_Reverts_For_Unsupported_Token() public {
        uint256 daiAmount = 10e18; // $10 DAI

        vm.startPrank(USER);
        dai.approve(address(fractionalOwnership), daiAmount);
        
        vm.expectRevert(TokenNotSupported.selector);
        fractionalOwnership.contributeStablecoin(address(dai), daiAmount);
        vm.stopPrank();
    }

    function test_Contribute_Stablecoin_Reverts_When_Too_Small() public {
        uint256 tooSmallAmount = 1e5; // $0.1 USDT (6 decimals)

        vm.startPrank(USER);
        usdt.approve(address(fractionalOwnership), tooSmallAmount);
        
        vm.expectRevert(ContributionTooSmall.selector);
        fractionalOwnership.contributeStablecoin(address(usdt), tooSmallAmount);
        vm.stopPrank();
    }

    function test_Contribute_Stablecoin_Reverts_When_Not_KYC_Verified() public {
        uint256 usdtAmount = 10 * 1e6;

        usdt.mint(NON_KYC_USER, usdtAmount);
        
        vm.startPrank(NON_KYC_USER);
        usdt.approve(address(fractionalOwnership), usdtAmount);
        
        vm.expectRevert(KYCNotCompleted.selector);
        fractionalOwnership.contributeStablecoin(address(usdt), usdtAmount);
        vm.stopPrank();
    }

    ///////////////////////////////
    // Fiat Payment Tests //
    /////////////////////////////
    function test_Process_Fiat_Payment_Success() public {
    uint256 usdAmount = 100e18; // $100
    string memory txRef = "STRIPE_TX_123456";

    vm.prank(FIAT_PROCESSOR);
    
    // Change the order - expect ContributionMade first, then FiatPaymentProcessed
    vm.expectEmit(true, true, false, true);
    emit ContributionMade(
        USER,
        address(0),
        0,
        usdAmount,
        usdAmount,
        FractionalOwnership.PaymentMethod.FIAT_ONRAMP
    );
    
    vm.expectEmit(true, false, false, true);
    emit FiatPaymentProcessed(USER, usdAmount, txRef);

    fractionalOwnership.processFiatPayment(USER, usdAmount, txRef);

    // Check that transaction is marked as processed
    assertTrue(fractionalOwnership.processedFiatTransactions(txRef));

    // Check user got tokens
    assertEq(fractionalOwnershipToken.balanceOf(USER), usdAmount);

    // Check contribution tracking
    FractionalOwnership.UserContribution memory contribution = fractionalOwnership.getUserContribution(USER);
    assertEq(contribution.totalUsdContributed, usdAmount);
    assertEq(contribution.totalTokensReceived, usdAmount);
}

    function test_Process_Fiat_Payment_Reverts_When_Not_Fiat_Processor() public {
        vm.prank(USER);
        vm.expectRevert();
        fractionalOwnership.processFiatPayment(USER, 100e18, "TX_123");
    }

    function test_Process_Fiat_Payment_Reverts_When_User_Not_KYC_Verified() public {
        vm.prank(FIAT_PROCESSOR);
        vm.expectRevert(KYCNotCompleted.selector);
        fractionalOwnership.processFiatPayment(NON_KYC_USER, 100e18, "TX_123");
    }

    function test_Process_Fiat_Payment_Reverts_When_Duplicate_Transaction() public {
        string memory txRef = "TX_123";

        vm.startPrank(FIAT_PROCESSOR);
        
        // First payment should succeed
        fractionalOwnership.processFiatPayment(USER, 100e18, txRef);
        
        // Second payment with same ref should fail
        vm.expectRevert(InvalidAmount.selector);
        fractionalOwnership.processFiatPayment(USER, 100e18, txRef);
        
        vm.stopPrank();
    }

    function test_Process_Fiat_Payment_Reverts_When_Too_Small() public {
        vm.prank(FIAT_PROCESSOR);
        vm.expectRevert(ContributionTooSmall.selector);
        fractionalOwnership.processFiatPayment(USER, 0.5e18, "TX_123"); // $0.5
    }

    //////////////////////////
    // Admin Function Tests //
    /////////////////////////
    function test_Update_KYC_Status_Success() public {
        address newUser = makeAddr("newUser");
        
        vm.prank(ADMIN);
        vm.expectEmit(true, false, false, true);
        emit KYCStatusUpdated(newUser, true);
        
        fractionalOwnership.updateKYCStatus(newUser, true);
        
        FractionalOwnership.UserContribution memory contribution = fractionalOwnership.getUserContribution(newUser);
        assertTrue(contribution.isKYCVerified);
    }

    function test_Update_KYC_Status_Reverts_When_Not_Admin() public {
        vm.prank(USER);
        vm.expectRevert();
        fractionalOwnership.updateKYCStatus(USER, true);
    }

    function test_Batch_Update_KYC_Status() public {
        address[] memory users = new address[](2);
        bool[] memory statuses = new bool[](2);
        
        users[0] = makeAddr("user1");
        users[1] = makeAddr("user2");
        statuses[0] = true;
        statuses[1] = false;

        vm.prank(ADMIN);
        fractionalOwnership.batchUpdateKYCStatus(users, statuses);

        assertTrue(fractionalOwnership.getUserContribution(users[0]).isKYCVerified);
        assertFalse(fractionalOwnership.getUserContribution(users[1]).isKYCVerified);
    }

    function test_Add_Stablecoin_Success() public {
        vm.prank(ADMIN);
        
        vm.expectEmit(true, false, false, true);
        emit StablecoinAdded(address(dai), 18);
        
        fractionalOwnership.addStablecoin(address(dai), 18, address(0));
        
        assertTrue(fractionalOwnership.isStablecoinSupported(address(dai)));
    }

    function test_Remove_Stablecoin_Success() public {
        vm.prank(ADMIN);
        
        vm.expectEmit(true, false, false, false);
        emit StablecoinRemoved(address(usdt));
        
        fractionalOwnership.removeStablecoin(address(usdt));
        
        assertFalse(fractionalOwnership.isStablecoinSupported(address(usdt)));
    }

    function test_Pause_And_Unpause() public {
        vm.startPrank(ADMIN);
        
        // Test pause
        fractionalOwnership.pause();
        assertTrue(fractionalOwnership.paused());
        
        // Test unpause
        fractionalOwnership.unpause();
        assertFalse(fractionalOwnership.paused());
        
        vm.stopPrank();
    }

    function test_Emergency_Withdraw_ETH() public {
    // Send some ETH to contract first
    vm.prank(USER);
    fractionalOwnership.contributeETH{value: 1 ether}();
    
    uint256 contractBalance = address(fractionalOwnership).balance;
    uint256 adminBalanceBefore = ADMIN.balance;
    
    // Grant DEFAULT_ADMIN_ROLE to ADMIN using the test contract's privileges
    vm.prank(address(this)); // Test contract is the deployer and has DEFAULT_ADMIN_ROLE
    fractionalOwnership.grantRole(fractionalOwnership.DEFAULT_ADMIN_ROLE(), ADMIN);
    
    // Emergency withdraw
    vm.prank(ADMIN);
    fractionalOwnership.emergencyWithdraw(address(0), contractBalance);
    
    assertEq(address(fractionalOwnership).balance, 0);
    assertEq(ADMIN.balance, adminBalanceBefore + contractBalance);
    }

    function test_Emergency_Withdraw_Token() public {
    uint256 usdtAmount = 100 * 1e6;
    
    // Contribute USDT first
    vm.startPrank(USER);
    usdt.approve(address(fractionalOwnership), usdtAmount);
    fractionalOwnership.contributeStablecoin(address(usdt), usdtAmount);
    vm.stopPrank();
    
    uint256 contractBalance = usdt.balanceOf(address(fractionalOwnership));
    uint256 testContractBalanceBefore = usdt.balanceOf(address(this));
    
    // Emergency withdraw using test contract's DEFAULT_ADMIN_ROLE
    fractionalOwnership.emergencyWithdraw(address(usdt), contractBalance);
    
    assertEq(usdt.balanceOf(address(fractionalOwnership)), 0);
    assertEq(usdt.balanceOf(address(this)), testContractBalanceBefore + contractBalance);
    }

    //////////////////////////
    // View Function Tests //
    /////////////////////////
    function test_Get_Eth_Value_In_Usd() public view {
        uint256 ethAmount = 1 ether;
        uint256 expectedValue = uint256(INITIAL_PRICE) * ethAmount / 1e8; // Price feed has 8 decimals
        
        assertEq(fractionalOwnership.getEthValueInUsd(ethAmount), expectedValue);
    }

    function test_Get_Contract_Balances() public {
        // Contribute some assets first
        vm.prank(USER);
        fractionalOwnership.contributeETH{value: 1 ether}();
        
        vm.startPrank(USER);
        usdt.approve(address(fractionalOwnership), 100 * 1e6);
        fractionalOwnership.contributeStablecoin(address(usdt), 100 * 1e6);
        vm.stopPrank();

        (uint256 ethBalance, address[] memory tokens, uint256[] memory tokenBalances) = 
            fractionalOwnership.getContractBalances();

        assertEq(ethBalance, 1 ether);
        assertEq(tokens.length, 2); // USDT and USDC
        assertEq(tokenBalances[0], 100 * 1e6); // USDT balance
    }

    function test_Calculate_Tokens_For_Amount() public view {
        // Test ETH calculation
        uint256 ethAmount = 1 ether;
        uint256 expectedTokensFromETH = fractionalOwnership.getEthValueInUsd(ethAmount);
        assertEq(fractionalOwnership.calculateTokensForAmount(address(0), ethAmount), expectedTokensFromETH);
        
        // Test USDT calculation
        uint256 usdtAmount = 100 * 1e6; // $100 USDT
        uint256 expectedTokensFromUSDT = 100e18; // $100 in 18 decimals
        assertEq(fractionalOwnership.calculateTokensForAmount(address(usdt), usdtAmount), expectedTokensFromUSDT);
        
        // Test unsupported token
        assertEq(fractionalOwnership.calculateTokensForAmount(address(dai), 100e18), 0);
    }

    //////////////////////////
    // Integration Tests //
    /////////////////////////
    function test_Multiple_Contributions_And_Limits() public {
        // Test that a user can make multiple contributions up to the limit
        uint256 contribution1 = 30000e18; // $30k
        uint256 contribution2 = 40000e18; // $40k
        uint256 contribution3 = 30000e18; // $30k
        uint256 contribution4 = 1e18; // $1 - should fail due to limit

        // First contribution via fiat
        vm.prank(FIAT_PROCESSOR);
        fractionalOwnership.processFiatPayment(USER, contribution1, "TX_001");

        // Second contribution via USDT
        uint256 usdtAmount = 40000 * 1e6; // $40k USDT
        usdt.mint(USER, usdtAmount);
        vm.startPrank(USER);
        usdt.approve(address(fractionalOwnership), usdtAmount);
        fractionalOwnership.contributeStablecoin(address(usdt), usdtAmount);
        vm.stopPrank();

        // Third contribution via ETH (set ETH price to $3000 to make calculation easier)
        ethUsdPriceFeed.updateAnswer(3000e8);
        uint256 ethAmount = 10 ether; // 10 ETH * $3000 = $30k
        vm.deal(USER, ethAmount);
        vm.prank(USER);
        fractionalOwnership.contributeETH{value: ethAmount}();

        // Check total contributions
        FractionalOwnership.UserContribution memory contribution = fractionalOwnership.getUserContribution(USER);
        assertEq(contribution.totalUsdContributed, contribution1 + contribution2 + contribution3);

        // Fourth contribution should fail due to limit
        vm.prank(FIAT_PROCESSOR);
        vm.expectRevert(ContributionLimitExceeded.selector);
        fractionalOwnership.processFiatPayment(USER, contribution4, "TX_002");
    }

    function test_Unique_Contributor_Tracking() public {
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");

    // Setup KYC for all users
    vm.startPrank(ADMIN);
    fractionalOwnership.updateKYCStatus(user1, true);
    fractionalOwnership.updateKYCStatus(user2, true);
    fractionalOwnership.updateKYCStatus(user3, true);
    vm.stopPrank();

    // Initial state - no contributions yet
    assertEq(fractionalOwnership.s_uniqueContributors(), 0);

    // User1 contributes
    vm.deal(user1, 1 ether);
    vm.prank(user1);
    fractionalOwnership.contributeETH{value: MIN_CONTRIBUTION_ETH}();
    assertEq(fractionalOwnership.s_uniqueContributors(), 1);

    // User1 contributes again (shouldn't increase unique count)
    vm.prank(user1);
    fractionalOwnership.contributeETH{value: MIN_CONTRIBUTION_ETH}();
    assertEq(fractionalOwnership.s_uniqueContributors(), 1);

    // User2 contributes
    vm.deal(user2, 1 ether);
    vm.prank(user2);
    fractionalOwnership.contributeETH{value: MIN_CONTRIBUTION_ETH}();
    assertEq(fractionalOwnership.s_uniqueContributors(), 2);

    // User3 contributes via fiat
    vm.prank(FIAT_PROCESSOR);
    fractionalOwnership.processFiatPayment(user3, 10e18, "TX_USER3");
    assertEq(fractionalOwnership.s_uniqueContributors(), 3);
    }

    ///////////////////////////////
    // Price Feed Edge Cases //
    /////////////////////////////
    function test_Invalid_Price_Data_Reverts() public {
        // Deploy a mock that returns invalid data
        MockV3Aggregator badPriceFeed = new MockV3Aggregator(8, -1); // Negative price
        
        FractionalOwnership badContract = new FractionalOwnership(
            address(badPriceFeed),
            address(usdt),
            address(usdc)
        );

        badContract.updateKYCStatus(USER, true);
        
        vm.deal(USER, 1 ether);
        vm.prank(USER);
        vm.expectRevert(InvalidPriceData.selector);
        badContract.contributeETH{value: 1 ether}();
    }

    ////////////////////////
    // Helper Tests //
    //////////////////////
    function test_Receive_Function() public {
        // Test that contract can receive ETH directly
        (bool success,) = payable(address(fractionalOwnership)).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(fractionalOwnership).balance, 1 ether);
    }

    ////////////////////////
    // Edge Case Tests //
    //////////////////////
    function test_Zero_Value_Contribution_Reverts() public {
        vm.prank(USER);
        vm.expectRevert(ContributionTooSmall.selector);
        fractionalOwnership.contributeETH{value: 0}();
    }

    function test_Zero_Address_Stablecoin_Reverts() public {
        vm.prank(ADMIN);
        vm.expectRevert(InvalidAddress.selector);
        fractionalOwnership.addStablecoin(address(0), 18, address(0));
    }

    function test_Remove_Non_Existent_Stablecoin_Reverts() public {
        vm.prank(ADMIN);
        vm.expectRevert(TokenNotSupported.selector);
        fractionalOwnership.removeStablecoin(address(dai));
    }
}