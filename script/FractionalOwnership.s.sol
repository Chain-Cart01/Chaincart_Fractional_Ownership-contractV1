// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {FractionalOwnership} from "../src/FractionalOwnership.sol";

contract DeployFractionalOwnership is Script {
    function run() external returns (FractionalOwnership, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        
        // Use the new getter function instead
        address ethUsdPriceFeed = helperConfig.getActiveNetworkConfig();

        vm.startBroadcast();
        FractionalOwnership fractionalOwnership = new FractionalOwnership(ethUsdPriceFeed);
        vm.stopBroadcast();
        return (fractionalOwnership, helperConfig);
    }
}