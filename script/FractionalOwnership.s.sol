// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {FractionalOwnership} from "../src/FractionalOwnership.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployFractionalOwnership is Script {
    function run() external returns (FractionalOwnership, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        address ethUsdPriceFeed = helperConfig.getActiveNetworkConfig();
    
        address usdt = address(0);
        address usdc = address(0);

        vm.startBroadcast();
        FractionalOwnership fractionalOwnership = new FractionalOwnership(
            ethUsdPriceFeed,
            usdt,
            usdc
        );
        vm.stopBroadcast();

        return (fractionalOwnership, helperConfig);
    } 
}