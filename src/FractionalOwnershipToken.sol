// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title FractionalOwnershipToken
 * @author SALAMI SELIM
 * @notice Simple ERC20 token for fractional ownership shares
 * @dev Only the FractionalOwnership contract can mint tokens
 */
contract FractionalOwnershipToken is ERC20 {
    address public immutable i_fractionalOwnershipContract;

    // ERROR
    error FractionalOwnershipToken__OnlyOwnershipContract();

    // MODIFIER
    modifier onlyOwnershipContract() {
        if (msg.sender != i_fractionalOwnershipContract) {
            revert FractionalOwnershipToken__OnlyOwnershipContract();
        }
        _;
    }

    // CONSTRUCTOR
    constructor() ERC20("ChainCart Token", "CC_Shares") {
        i_fractionalOwnershipContract = msg.sender;
    }

     // Mint tokens to user
    function mint(address to, uint256 amount) external onlyOwnershipContract returns (bool) {
        _mint(to, amount);
        return true;
    }

     // Get the FractionalOwnership contract address

    function getFractionalOwnershipContract() external view returns (address) {
        return i_fractionalOwnershipContract;
    }
}
