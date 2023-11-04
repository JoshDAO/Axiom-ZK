// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MyERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000 * 1e18);
        _mint(address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266), 100 * 1e18);
        _mint(address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8), 100 * 1e18);
        _mint(address(0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC), 100 * 1e18);
    }
}
