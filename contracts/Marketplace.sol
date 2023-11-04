pragma solidity ^0.8.20;

import "./Otoken.sol";
import "./library/EnumerableSet.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {BokkyPooBahsDateTimeLibrary} from "./library/BokkyPooBahsDateTimeLibrary.sol";
import {Strings} from "./library/Strings.sol";

import "hardhat/console.sol";

/**
 * SPDX-License-Identifier: UNLICENSED
 * @title A contract to allow sellers to mint and sell binary options
 * @notice Create new oTokens and keep track of all created tokens
 * @notice For simplicity, this contract only allows orders of size 1.
 * @notice This contract does not allow a seller to have multiple of the same option for sale simultaneously.
 * @notice If a seller attempts to sell the same option while he already has an unmatched sell order, it will simply update their sell price
 */
contract Marketplace {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev weth contract address
    address weth;

    /// @dev usdc contract address
    address usdc;

    /// @dev enumerable address set of all oToken addresses currently for sale
    EnumerableSet.AddressSet optionsForSale;

    /// @dev mapping from seller address to list of all oToken contracts it has deployed that have not all been closed
    mapping(address => EnumerableSet.AddressSet) private otokensBySeller;

    // @dev mapping of buyer address to list of all oToken contracts it has bought that have not been closed
    mapping(address => EnumerableSet.AddressSet) private otokensByBuyer;

    /// @dev mapping from oTokenAddress to sale info
    mapping(address => OptionSaleInfo) public optionSaleInfo;

    // @dev mapping from token ID to address
    mapping(bytes32 => address) public idToAddress;

    /// @dev max expiry (2345/12/31)
    uint256 private constant MAX_EXPIRY = 11865398400;
    uint256 private constant STRIKE_PRICE_SCALE = 1e6;
    uint256 private constant STRIKE_PRICE_DIGITS = 6;

    struct OptionSaleInfo {
        bool currentlyForSale; // true if there is an unmatched sale order
        uint price; // denominated in WETH between 0 and 1e18
        uint numberContractsMatched; // counts the cumulative number of contracts that have been sold
    }

    constructor(address _weth, address _usdc) {
        weth = _weth;
        usdc = _usdc;
    }

    /// @notice emitted when the factory creates a new Option
    event OtokenCreated(
        address tokenAddress,
        address creator,
        uint256 strikePrice,
        uint256 expiry,
        bool isPut
    );

    // ======== marketplace functions =========

    /**
     * @notice allows a seller to put one option on the marketplace, fully collateralised with 1 WETH.
     *         Checks if this seller has already deployed a contract representing this option series (strike, expiry, direction)
     *         If not, deploys an oToken contract, takes 1 WETH from seller's address as collateral, and mints an option from the oToken contract
     *         If contract already exists, locates the existing contract address and mints from that.
     * @param _strikePrice strike price with decimals = 6
     * @param _expiry expiration timestamp as a unix timestamp
     * @param _isPut True if a put option, False if a call option
     * @param _price Price of the option, denominated in WETH. e18. Must be between 0 and 1e18.
     * @return oTokenAddress address of the newly created option
     */
    function sellOption(
        uint256 _strikePrice,
        uint256 _expiry,
        bool _isPut,
        uint256 _price
    ) external returns (address oTokenAddress) {
        bytes32 tokenId = _getOptionId(
            _strikePrice,
            _expiry,
            _isPut,
            msg.sender
        );

        // this value will be the zero address if does not exist
        oTokenAddress = idToAddress[tokenId];

        if (oTokenAddress == address(0)) {
            // in this case we need to deploy an oToken contract
            oTokenAddress = _createOtoken(_strikePrice, _expiry, _isPut);
        }
        if (ERC20(oTokenAddress).balanceOf(address(this)) == 1e18) {
            // if this contract already holds a token of this address, the seller already has one for sale, so simply reprice the token
            optionSaleInfo[oTokenAddress].price = _price;
            return oTokenAddress;
        } else {
            // transfer 1 WETH of collateral to the marketplace.
            ERC20(weth).transferFrom(msg.sender, address(this), 1e18);
        }

        Otoken(oTokenAddress).mintOtoken(address(this), 1e18);
        optionSaleInfo[oTokenAddress].price = _price;
        optionSaleInfo[oTokenAddress].currentlyForSale = true;
        optionsForSale.add(oTokenAddress);
        otokensBySeller[msg.sender].add(oTokenAddress);
    }

    function buyOption(address _oTokenAddress, address _seller) external {
        // first check that this option is available to sell
        require(
            otokensBySeller[_seller].contains(_oTokenAddress),
            "invalid option"
        );
        OptionSaleInfo memory saleInfo = optionSaleInfo[_oTokenAddress];
        require(saleInfo.currentlyForSale, "option is not for sale");

        require(ERC20(_oTokenAddress).balanceOf(address(this)) == 1e18);

        // take payment for the option and send to seller
        ERC20(weth).transferFrom(
            msg.sender,
            Otoken(_oTokenAddress).seller(),
            saleInfo.price
        );

        // send otoken to buyer
        ERC20(_oTokenAddress).transfer(msg.sender, 1e18);

        optionsForSale.remove(_oTokenAddress);
        optionSaleInfo[_oTokenAddress].price = 0;
        optionSaleInfo[_oTokenAddress].currentlyForSale = false;
        optionSaleInfo[_oTokenAddress].numberContractsMatched += 1;
        otokensByBuyer[msg.sender].add(_oTokenAddress);
    }

    /**
     * @notice allows a seller of an option that expired OTM to redeem their 1 WETH of collateral.
     *         Checks option contracct is expired.
     *         Checks if this seller has outstanding short contracts of this option series (strike, expiry, direction)
     *         If so, send 1 WETH to the seller for each contract they have sold
     * @param _strikePrice strike price with decimals = 6
     * @param _expiry expiration timestamp as a unix timestamp
     * @param _isPut True if a put option, False if a call option
     */
    function redeemCollateral(
        uint256 _strikePrice,
        uint256 _expiry,
        bool _isPut
    ) external {
        require(_expiry < block.timestamp, "Option must be expired:");
        address otokenAddress = getOtoken(
            _strikePrice,
            _expiry,
            _isPut,
            msg.sender
        );
        require(
            otokensBySeller[msg.sender].contains(otokenAddress),
            "user has not sold this option"
        );
        // TODO: check that the strike price was NOT touched at any point before releasing collateral back to seller

        uint256 numberOfContracts = optionSaleInfo[otokenAddress]
            .numberContractsMatched;

        ERC20(weth).transfer(msg.sender, numberOfContracts * 1e18);

        // remove this contract from storage since it is settled.
        delete optionSaleInfo[otokenAddress];
        otokensBySeller[msg.sender].remove(otokenAddress);
    }

    /**
     * @notice allows a buyer of an option that expired ITM to redeem their 1 WETH payout.
     *         Checks option contracct is expired.
     *         Transfers the quantity of oTokens to this address to be burned
     *         Checks price touched the strike price using ZK proofs
     *         Sends the buyer 1 WETH for each contract they own
     * @param _oTokenAddress address of the otoken contract to be redeemed
     * @param _quantity number of contracts to be redeemed. e18
     */
    function redeemOption(address _oTokenAddress, uint256 _quantity) external {
        uint expiry = Otoken(_oTokenAddress).expiryTimestamp();
        require(expiry < block.timestamp, "Option must be expired");
        require(_quantity % 1e18 == 0, "must be whole number of contracts");
        address seller = Otoken(_oTokenAddress).seller();
        uint256 strikePrice = Otoken(_oTokenAddress).strikePrice();

        //TODO: check price touched strike price between issuance and expiry using zk proofs

        // send otokens to burn address
        ERC20(_oTokenAddress).transferFrom(msg.sender, address(0), _quantity);
        ERC20(weth).transfer(msg.sender, _quantity);

        optionSaleInfo[_oTokenAddress].numberContractsMatched -=
            _quantity /
            1e18;

        if (optionSaleInfo[_oTokenAddress].numberContractsMatched == 0) {
            // remove this contract from storage since all open contracts have been redeemed.
            delete optionSaleInfo[_oTokenAddress];
            otokensBySeller[msg.sender].remove(_oTokenAddress);
        }
    }

    /**
     * @notice allows a seller of an option that expired OTM to redeem their 1 WETH of collateral.
     *         Checks option contracct is expired.
     *         Checks if this seller has outstanding short contracts of this option series (strike, expiry, direction)
     *         If so, send 1 WETH to the seller for each contract they have sold
     * @param _strikePrice strike price with decimals = 6
     * @param _expiry expiration timestamp as a unix timestamp
     * @param _isPut True if a put option, False if a call option
     */
    function redeemCollateral(
        uint256 _strikePrice,
        uint256 _expiry,
        bool _isPut
    ) external {
        require(_expiry < block.timestamp, "Option must be expired:");
        address otokenAddress = getOtoken(
            _strikePrice,
            _expiry,
            _isPut,
            msg.sender
        );
        require(
            otokensBySeller[msg.sender].contains(otokenAddress),
            "user has not sold this option"
        );
        // TODO: check that the strike price was NOT touched at any point before releasing collateral back to seller

        uint256 numberOfContracts = optionSaleInfo[otokenAddress]
            .numberContractsMatched;

        ERC20(weth).transfer(msg.sender, numberOfContracts * 1e18);

        // remove this contract from storage since it is settled.
        delete optionSaleInfo[otokenAddress];
        otokensBySeller[msg.sender].remove(otokenAddress);
    }

    /**
     * @notice allows a buyer of an option that expired ITM to redeem their 1 WETH payout.
     *         Checks option contracct is expired.
     *         Transfers the quantity of oTokens to this address to be burned
     *         Checks price touched the strike price using ZK proofs
     *         Sends the buyer 1 WETH for each contract they own
     * @param _oTokenAddress address of the otoken contract to be redeemed
     * @param _quantity number of contracts to be redeemed. e18
     */
    function redeemOption(address _oTokenAddress, uint256 _quantity) external {
        uint expiry = Otoken(_oTokenAddress).expiryTimestamp();
        require(expiry < block.timestamp, "Option must be expired");
        require(_quantity % 1e18 == 0, "must be whole number of contracts");
        address seller = Otoken(_oTokenAddress).seller();
        uint256 strikePrice = Otoken(_oTokenAddress).strikePrice();

        //TODO: check price touched strike price between issuance and expiry using zk proofs

        // send otokens to burn address
        ERC20(_oTokenAddress).transferFrom(msg.sender, address(0), _quantity);
        ERC20(weth).transfer(msg.sender, _quantity);

        optionSaleInfo[_oTokenAddress].numberContractsMatched -=
            _quantity /
            1e18;

        if (optionSaleInfo[_oTokenAddress].numberContractsMatched == 0) {
            // remove this contract from storage since all open contracts have been redeemed.
            delete optionSaleInfo[_oTokenAddress];
            otokensBySeller[msg.sender].remove(_oTokenAddress);
        }
    }

    function getOptionsForSale() public view returns (address[] memory) {
        return optionsForSale.values();
    }

    function getOptionsForSaleBySeller(
        address _seller
    ) public view returns (address[] memory) {
        return otokensBySeller[_seller].values();
    }

    function getOptionsBoughtByBuyer(
        address _buyer
    ) public view returns (address[] memory) {
        return otokensByBuyer[_buyer].values();
    }

    // ======== oToken functions =========

    /**
     * @notice create new oTokens
     * @param _strikePrice strike price with decimals = 6
     * @param _expiry expiration timestamp as a unix timestamp
     * @param _isPut True if a put option, False if a call option
     * @return newOtoken address of the newly created option
     */
    function _createOtoken(
        uint256 _strikePrice,
        uint256 _expiry,
        bool _isPut
    ) internal returns (address) {
        require(
            _expiry > block.timestamp,
            "OtokenFactory: Can't create expired option"
        );
        require(
            _expiry < MAX_EXPIRY,
            "OtokenFactory: Can't create option with expiry > 2345/12/31"
        );
        // 8 hours = 3600 * 8 = 28800 seconds
        // require(
        //     (_expiry - 28800) % (86400) == 0,
        //     "OtokenFactory: Option has to expire 08:00 UTC"
        // );

        (
            string memory tokenName,
            string memory tokenSymbol
        ) = _getNameAndSymbol(_strikePrice, _expiry, _isPut);
        address newOtoken = address(
            new Otoken(
                _strikePrice,
                _expiry,
                _isPut,
                msg.sender,
                address(this),
                tokenName,
                tokenSymbol
            )
        );
        bytes32 tokenId = _getOptionId(
            _strikePrice,
            _expiry,
            _isPut,
            msg.sender
        );
        idToAddress[tokenId] = newOtoken;
        otokensBySeller[msg.sender].add(newOtoken);

        emit OtokenCreated(
            newOtoken,
            msg.sender,
            _strikePrice,
            _expiry,
            _isPut
        );

        return newOtoken;
    }

    /**
     * @notice get the total number of open oToken contracts sold by an address
     * @param _seller address that minted oToken contract
     * @return length of the oTokens array
     */
    function getOtokensBySellerLength(
        address _seller
    ) external view returns (uint256) {
        return otokensBySeller[_seller].length();
    }

    /**
     * @notice get the oToken address for an already created oToken, if no oToken has been created with these parameters, it will return address(0)
     * @param _strikePrice strike price with decimals = 6
     * @param _expiry expiration timestamp as a unix timestamp
     * @param _isPut True if a put option, False if a call option
     * @param _seller address that minted oToken contract
     * @return the address of target otoken.
     */
    function getOtoken(
        uint256 _strikePrice,
        uint256 _expiry,
        bool _isPut,
        address _seller
    ) public view returns (address) {
        bytes32 id = _getOptionId(_strikePrice, _expiry, _isPut, _seller);
        return idToAddress[id];
    }

    /**
     * @dev hash oToken parameters and return a unique option id
     * @param _strikePrice strike price with decimals = 6
     * @param _expiry expiration timestamp as a unix timestamp
     * @param _isPut True if a put option, False if a call option
     * @param _seller address that minted oToken contract
     * @return id the unique id of an oToken
     */
    function _getOptionId(
        uint256 _strikePrice,
        uint256 _expiry,
        bool _isPut,
        address _seller
    ) internal pure returns (bytes32) {
        return
            keccak256(abi.encodePacked(_strikePrice, _expiry, _isPut, _seller));
    }

    // ======== oToken naming functions =========

    /**
     * @notice generates the name and symbol for an option
     * @dev this function uses a named return variable to avoid the stack-too-deep error
     * @return tokenName (ex: ETHUSDC 05-September-2020 200 Put USDC Collateral)
     * @return tokenSymbol (ex: oETHUSDC-05SEP20-200P)
     */
    function _getNameAndSymbol(
        uint256 strikePrice,
        uint256 expiryTimestamp,
        bool isPut
    )
        internal
        pure
        returns (string memory tokenName, string memory tokenSymbol)
    {
        string memory displayStrikePrice = _getDisplayedStrikePrice(
            strikePrice
        );

        // convert expiry to a readable string
        (uint256 year, uint256 month, uint256 day) = BokkyPooBahsDateTimeLibrary
            .timestampToDate(expiryTimestamp);

        // get option type string
        (string memory typeSymbol, string memory typeFull) = _getOptionType(
            isPut
        );

        //get option month string
        (string memory monthSymbol, string memory monthFull) = _getMonth(month);

        // concatenated name string: ETHUSDC 05-September-2020 200 Put USDC Collateral
        tokenName = string(
            abi.encodePacked(
                "ETH",
                "USD",
                " ",
                _uintTo2Chars(day),
                "-",
                monthFull,
                "-",
                Strings.toString(year),
                " ",
                displayStrikePrice,
                typeFull,
                " "
            )
        );

        // concatenated symbol string: oETHUSDC/USDC-05SEP20-200P
        tokenSymbol = string(
            abi.encodePacked(
                "o",
                "ETH",
                "USD",
                "-",
                _uintTo2Chars(day),
                monthSymbol,
                _uintTo2Chars(year),
                "-",
                displayStrikePrice,
                typeSymbol
            )
        );
    }

    /**
     * @dev convert strike price scaled by 1e8 to human readable number string
     * @param _strikePrice strike price scaled by 1e8
     * @return strike price string
     */
    function _getDisplayedStrikePrice(
        uint256 _strikePrice
    ) internal pure returns (string memory) {
        uint256 remainder = _strikePrice % STRIKE_PRICE_SCALE;
        uint256 quotient = _strikePrice / STRIKE_PRICE_SCALE;
        console.logUint(remainder);
        console.logUint(quotient);
        string memory quotientStr = Strings.toString(quotient);

        if (remainder == 0) return quotientStr;

        uint256 trailingZeroes;
        while (remainder % 10 == 0) {
            remainder = remainder / 10;
            trailingZeroes += 1;
        }

        // pad the number with "1 + starting zeroes"
        remainder += 10 ** (STRIKE_PRICE_DIGITS - trailingZeroes);

        string memory tmpStr = Strings.toString(remainder);
        tmpStr = _slice(tmpStr, 1, 1 + STRIKE_PRICE_DIGITS - trailingZeroes);

        string memory completeStr = string(
            abi.encodePacked(quotientStr, ".", tmpStr)
        );
        return completeStr;
    }

    /**
     * @dev return a representation of a number using 2 characters, adds a leading 0 if one digit, uses two trailing digits if a 3 digit number
     * @return 2 characters that corresponds to a number
     */
    function _uintTo2Chars(
        uint256 number
    ) internal pure returns (string memory) {
        if (number > 99) number = number % 100;
        string memory str = Strings.toString(number);
        if (number < 10) {
            return string(abi.encodePacked("0", str));
        }
        return str;
    }

    /**
     * @dev return string representation of option type
     * @return shortString a 1 character representation of option type (P or C)
     * @return longString a full length string of option type (Put or Call)
     */
    function _getOptionType(
        bool _isPut
    )
        internal
        pure
        returns (string memory shortString, string memory longString)
    {
        if (_isPut) {
            return ("P", "Put");
        } else {
            return ("C", "Call");
        }
    }

    /**
     * @dev cut string s into s[start:end]
     * @param _s the string to cut
     * @param _start the starting index
     * @param _end the ending index (excluded in the substring)
     */
    function _slice(
        string memory _s,
        uint256 _start,
        uint256 _end
    ) internal pure returns (string memory) {
        bytes memory a = new bytes(_end - _start);
        for (uint256 i = 0; i < _end - _start; i++) {
            a[i] = bytes(_s)[_start + i];
        }
        return string(a);
    }

    /**
     * @dev return string representation of a month
     * @return shortString a 3 character representation of a month (ex: SEP, DEC, etc)
     * @return longString a full length string of a month (ex: September, December, etc)
     */
    function _getMonth(
        uint256 _month
    )
        internal
        pure
        returns (string memory shortString, string memory longString)
    {
        if (_month == 1) {
            return ("JAN", "January");
        } else if (_month == 2) {
            return ("FEB", "February");
        } else if (_month == 3) {
            return ("MAR", "March");
        } else if (_month == 4) {
            return ("APR", "April");
        } else if (_month == 5) {
            return ("MAY", "May");
        } else if (_month == 6) {
            return ("JUN", "June");
        } else if (_month == 7) {
            return ("JUL", "July");
        } else if (_month == 8) {
            return ("AUG", "August");
        } else if (_month == 9) {
            return ("SEP", "September");
        } else if (_month == 10) {
            return ("OCT", "October");
        } else if (_month == 11) {
            return ("NOV", "November");
        } else {
            return ("DEC", "December");
        }
    }
}
