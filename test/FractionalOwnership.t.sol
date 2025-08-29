// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {FractionalOwnership} from "../../src/FractionalOwnership.sol";
import {FractionalOwnershipToken} from "../../src/FractionalOwnershipToken.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
 
contract MockV3Aggregator {
    uint256 public constant version = 0;
    uint8 public decimals;
    int256 public latestAnswer;
    uint256 public latestTimestamp;
    uint256 public latestRound;

    mapping(uint256 => int256) public getAnswer;
    mapping(uint256 => uint256) public getTimestamp;
    mapping(uint256 => uint256) private getStartedAt;

    constructor(uint8 _decimals, int256 _initialAnswer) {
        decimals = _decimals;
        updateAnswer(_initialAnswer);
    }

    function updateAnswer(int256 _answer) public {
        latestAnswer = _answer;
        latestTimestamp = block.timestamp;
        latestRound++;
        getAnswer[latestRound] = _answer;
        getTimestamp[latestRound] = block.timestamp;
        getStartedAt[latestRound] = block.timestamp;
    }

    function updateRoundData(uint80 _roundId, int256 _answer, uint256 _timestamp, uint256 _startedAt) public {
        latestRound = _roundId;
        latestAnswer = _answer;
        latestTimestamp = _timestamp;
        getAnswer[latestRound] = _answer;
        getTimestamp[latestRound] = _timestamp;
        getStartedAt[latestRound] = _startedAt;
    }

    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, getAnswer[_roundId], getStartedAt[_roundId], getTimestamp[_roundId], _roundId);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (
            uint80(latestRound),
            getAnswer[latestRound],
            getStartedAt[latestRound],
            getTimestamp[latestRound],
            uint80(latestRound)
        );
    }
}

contract FractionalOwnershipTest is Test {
    FractionalOwnership fractionalOwnership;
    FractionalOwnershipToken token;
    MockV3Aggregator mockPriceFeed;

    // Redeclare the event for testing purposes
    event ContributionMade(address indexed user, uint256 ethAmount, uint256 usdValue, uint256 tokensIssued);

    address public USER1 = makeAddr("user1");
    address public USER2 = makeAddr("user2");
    
    uint256 public constant STARTING_USER_BALANCE = 100 ether;
    uint256 public constant MIN_USD_CONTRIBUTION = 1e18; // $1
    uint256 public constant MOCK_ETH_USD_PRICE = 2000e8; // $2000 with 8 decimals

    function setUp() public {
        // Deploy mock price feed with $2000 ETH price
        mockPriceFeed = new MockV3Aggregator(8, int256(MOCK_ETH_USD_PRICE));
        
        // Deploy fractional ownership with mock price feed
        fractionalOwnership = new FractionalOwnership(address(mockPriceFeed));
        token = FractionalOwnershipToken(fractionalOwnership.getTokenAddress());

        vm.deal(USER1, STARTING_USER_BALANCE);
        vm.deal(USER2, STARTING_USER_BALANCE);
    }

    //////////////////////////////////
    //////  CONSTRUCTOR TESTS ///////
    ////////////////////////////////
    function testConstructorSetsCorrectValues() public view {
        assertEq(fractionalOwnership.s_totalContributions(), 0);
        assertEq(fractionalOwnership.s_totalUsdValue(), 0);
        assertEq(fractionalOwnership.s_totalTokensIssued(), 0);
        assertEq(fractionalOwnership.getMinUsdContribution(), MIN_USD_CONTRIBUTION);
        assertEq(address(fractionalOwnership.getPriceFeedAddress()), address(mockPriceFeed));
    }

    function testTokenIsCreatedCorrectly() public view {
        assertEq(token.name(), "FractionOwnerToken");
        assertEq(token.symbol(), "FOT");
        assertEq(token.getFractionalOwnershipContract(), address(fractionalOwnership));
    }

    //////////////////////////////////////
    //////// PRICE FEED TESTS ///////////
    ////////////////////////////////////
    function testPriceFeedWorksCorrectly() public view {
        uint256 ethPrice = fractionalOwnership.getEthUsdPrice();
        assertEq(ethPrice, MOCK_ETH_USD_PRICE);
    }

    function testEthToUsdConversion() public view {
        uint256 ethAmount = 1 ether;
        uint256 usdValue = fractionalOwnership.getEthValueInUsd(ethAmount);
        
        // 1 ETH * $2000 = $2000 USD
        uint256 expectedUsd = 2000e18; // $2000 with 18 decimals
        assertEq(usdValue, expectedUsd);
    }

    function testMinimumEthForUsdContribution() public view {
        uint256 minEthRequired = fractionalOwnership.getMinEthForUsdContribution();
        
        // For $1 at $2000/ETH price: $1 / $2000 = 0.0005 ETH
        uint256 expectedMinEth = 0.0005 ether;
        assertEq(minEthRequired, expectedMinEth);
    }

    ////////////////////////////////////////
    //////// CONTRIBUTION TESTS ///////////
    //////////////////////////////////////
    function testContributeSuccessfully() public {
        uint256 ethContribution = 0.1 ether; // 0.1 ETH
        uint256 expectedUsdValue = 200e18; // 0.1 * $2000 = $200
        uint256 expectedTokens = 200e18; // $200 = 200 tokens
        
        vm.prank(USER1);
        fractionalOwnership.contribute{value: ethContribution}();

        assertEq(fractionalOwnership.s_totalContributions(), ethContribution);
        assertEq(fractionalOwnership.s_totalUsdValue(), expectedUsdValue);
        assertEq(fractionalOwnership.s_totalTokensIssued(), expectedTokens);
        assertEq(fractionalOwnership.getUserEthContribution(USER1), ethContribution);
        assertEq(fractionalOwnership.getUserUsdContribution(USER1), expectedUsdValue);
        assertEq(token.balanceOf(USER1), expectedTokens);
    }

    function testContributeEmitsCorrectEvent() public {
        uint256 ethContribution = 0.05 ether; // 0.05 ETH
        uint256 expectedUsdValue = 100e18; // 0.05 * $2000 = $100
        uint256 expectedTokens = 100e18; // $100 = 100 tokens
        
        vm.expectEmit(true, false, false, true, address(fractionalOwnership));
        emit ContributionMade(USER1, ethContribution, expectedUsdValue, expectedTokens);
        
        vm.prank(USER1);
        fractionalOwnership.contribute{value: ethContribution}();
    }

    function testContributeFailsWithTooSmallUsdValue() public {
        // At $2000/ETH, need at least 0.0005 ETH for $1
        uint256 tooSmallContribution = 0.0001 ether; // Only $0.20 worth
        
        vm.expectRevert(FractionalOwnership.FractionalOwnership__ContributionTooSmall.selector);
        vm.prank(USER1);
        fractionalOwnership.contribute{value: tooSmallContribution}();
    }

    function testMultipleUsersContributeWithUsdBasis() public {
        uint256 ethContrib1 = 0.5 ether; // $1000 worth at $2000/ETH
        uint256 ethContrib2 = 1.25 ether; // $2500 worth at $2000/ETH
        
        uint256 expectedTokens1 = 1000e18; // $1000 = 1000 tokens
        uint256 expectedTokens2 = 2500e18; // $2500 = 2500 tokens
        
        vm.prank(USER1);
        fractionalOwnership.contribute{value: ethContrib1}();
        
        vm.prank(USER2);
        fractionalOwnership.contribute{value: ethContrib2}();

        assertEq(token.balanceOf(USER1), expectedTokens1);
        assertEq(token.balanceOf(USER2), expectedTokens2);
        assertEq(fractionalOwnership.s_totalUsdValue(), 3500e18); // $3500 total
    }

    function testSameUserMultipleContributions() public {
        uint256 ethContrib1 = 0.25 ether; // $500 worth
        uint256 ethContrib2 = 0.75 ether; // $1500 worth
        
        vm.startPrank(USER1);
        fractionalOwnership.contribute{value: ethContrib1}();
        fractionalOwnership.contribute{value: ethContrib2}();
        vm.stopPrank();

        assertEq(fractionalOwnership.getUserEthContribution(USER1), 1 ether);
        assertEq(fractionalOwnership.getUserUsdContribution(USER1), 2000e18); // $2000
        assertEq(token.balanceOf(USER1), 2000e18); // 2000 tokens
    }

    ////////////////////////////////////////
    /////////  PRICE CHANGE TESTS //////////
    ////////////////////////////////////////
    function testContributionWithDifferentEthPrices() public {
        uint256 ethAmount = 0.1 ether;
        
        // Test with $2000 ETH price
        vm.prank(USER1);
        fractionalOwnership.contribute{value: ethAmount}();
        assertEq(token.balanceOf(USER1), 200e18); // $200 = 200 tokens
        
        // Change ETH price to $3000
        mockPriceFeed.updateAnswer(3000e8);
        
        // Same ETH amount should now give more tokens
        vm.prank(USER2);
        fractionalOwnership.contribute{value: ethAmount}();
        assertEq(token.balanceOf(USER2), 300e18); // $300 = 300 tokens
    }

    function testMinimumContributionChangesWithPrice() public {
        // At $2000/ETH, minimum is 0.0005 ETH for $1
        uint256 minEthAt2000 = fractionalOwnership.getMinEthForUsdContribution();
        assertEq(minEthAt2000, 0.0005 ether);
        
        // Change price to $4000/ETH
        mockPriceFeed.updateAnswer(4000e8);
        
        // At $4000/ETH, minimum should be 0.00025 ETH for $1
        uint256 minEthAt4000 = fractionalOwnership.getMinEthForUsdContribution();
        assertEq(minEthAt4000, 0.00025 ether);
    }

    ////////////////////////////////////////
    //////// VIEW FUNCTIONS TESTS /////////
    //////////////////////////////////////
    function testCalculateTokensForEth() public view {
        uint256 ethAmount = 2 ether;
        uint256 expectedTokens = fractionalOwnership.calculateTokensForEth(ethAmount);
        
        // 2 ETH * $2000 = $4000 = 4000 tokens
        assertEq(expectedTokens, 4000e18);
    }

    function testViewFunctions() public {
        uint256 ethContribution = 1.5 ether;
        
        vm.prank(USER1);
        fractionalOwnership.contribute{value: ethContribution}();

        assertEq(fractionalOwnership.getUserEthContribution(USER1), ethContribution);
        assertEq(fractionalOwnership.getUserUsdContribution(USER1), 3000e18); // $3000
        assertEq(fractionalOwnership.getUserTokenBalance(USER1), 3000e18); // 3000 tokens
        assertEq(fractionalOwnership.getContractBalance(), ethContribution);
        assertEq(fractionalOwnership.getUsdToTokenRatio(), 1e18);
    }

    ///////////////////////////////////
    ////// INTEGRATION TESTS /////////
    /////////////////////////////////
    function testCompleteUsdBasedFlow() public {
        // USER1: Contributes 0.5 ETH ($1000 worth)
        uint256 ethAmount1 = 0.5 ether;
        vm.prank(USER1);
        fractionalOwnership.contribute{value: ethAmount1}();
        
        // USER2: Contributes 0.25 ETH ($500 worth)  
        uint256 ethAmount2 = 0.25 ether;
        vm.prank(USER2);
        fractionalOwnership.contribute{value: ethAmount2}();

        // Verify USD-based token distribution
        assertEq(token.balanceOf(USER1), 1000e18); // $1000 = 1000 tokens
        assertEq(token.balanceOf(USER2), 500e18);  // $500 = 500 tokens
        
        // Verify totals
        assertEq(fractionalOwnership.s_totalContributions(), 0.75 ether);
        assertEq(fractionalOwnership.s_totalUsdValue(), 1500e18); // $1500 total
        assertEq(fractionalOwnership.s_totalTokensIssued(), 1500e18); // 1500 tokens total
    }

    function testTokenDistributionIsUsdBased() public {
        // At $2000/ETH: 0.1 ETH = $200 = 200 tokens
        vm.prank(USER1);
        fractionalOwnership.contribute{value: 0.1 ether}();
        assertEq(token.balanceOf(USER1), 200e18);
        
        // Change ETH price to $1000
        mockPriceFeed.updateAnswer(1000e8);
        
        // At $1000/ETH: 0.1 ETH = $100 = 100 tokens
        vm.prank(USER2);
        fractionalOwnership.contribute{value: 0.1 ether}();
        assertEq(token.balanceOf(USER2), 100e18);
        
        // Both users contributed same ETH but got different tokens based on USD value
        assertNotEq(token.balanceOf(USER1), token.balanceOf(USER2));
    }

    ///////////////////////////////////
    /////// EDGE CASE TESTS ///////////
    //////////////////////////////////
    function testExactMinimumUsdContribution() public {
        // Calculate exact ETH needed for $1
        uint256 minEthNeeded = fractionalOwnership.getMinEthForUsdContribution();
        
        vm.prank(USER1);
        fractionalOwnership.contribute{value: minEthNeeded}();
        
        // Should receive exactly 1 token (for $1 USD)
        assertEq(token.balanceOf(USER1), 1e18);
    }

    function testLargeContribution() public {
        uint256 largeEthAmount = 10 ether; // $20,000 worth at $2000/ETH
        
        vm.prank(USER1);
        fractionalOwnership.contribute{value: largeEthAmount}();

        // Should receive 20,000 tokens
        assertEq(token.balanceOf(USER1), 20000e18);
        assertEq(fractionalOwnership.getUserUsdContribution(USER1), 20000e18);
    }
}