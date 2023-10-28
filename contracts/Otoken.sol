/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Otoken
 * @notice Otoken is the ERC20 token for an option
 */
contract Otoken is ERC20 {
    /// @notice address of the Controller module
    address public controller;

    /// @notice strike price with decimals = 6
    uint256 public strikePrice;

    /// @notice expiration timestamp of the option, represented as a unix timestamp
    uint256 public expiryTimestamp;

    /// @notice True if a put option, False if a call option
    bool public isPut;

    /// @notice the address of the person who deployed and sold this series
    address public seller;

    // @notice address of the binary option marketplace. Only calls from this address can mint and burn new tokens.
    address public marketplace;

    /**
     * @notice initialize the oToken
     * @param _strikePrice strike price with decimals = 6
     * @param _expiryTimestamp expiration timestamp of the option, represented as a unix timestamp
     * @param _isPut True if a put option, False if a call option
     * @param _seller the address that minted the token
     */
    constructor(
        uint256 _strikePrice,
        uint256 _expiryTimestamp,
        bool _isPut,
        address _seller,
        address _marketplace,
        string memory tokenName,
        string memory tokenSymbol
    ) ERC20(tokenName, tokenSymbol) {
        strikePrice = _strikePrice;
        expiryTimestamp = _expiryTimestamp;
        isPut = _isPut;
        seller = _seller;
        marketplace = _marketplace;
    }

    function getOtokenDetails()
        external
        view
        returns (uint256, uint256, bool, address)
    {
        return (strikePrice, expiryTimestamp, isPut, seller);
    }

    /**
     * @notice mint oToken for an account
     * @dev Controller only method where access control is taken care of by _beforeTokenTransfer hook
     * @param account account to mint token to
     * @param amount amount to mint
     */
    function mintOtoken(address account, uint256 amount) external {
        require(
            msg.sender == marketplace,
            "Otoken: Only Seller can mint Otokens"
        );
        _mint(account, amount);
    }

    /**
     * @notice burn oToken from an account.
     * @dev Controller only method where access control is taken care of by _beforeTokenTransfer hook
     * @param account account to burn token from
     * @param amount amount to burn
     */
    function burnOtoken(address account, uint256 amount) external {
        require(
            msg.sender == marketplace,
            "Otoken: Only Controller can burn Otokens"
        );
        _burn(account, amount);
    }
}
