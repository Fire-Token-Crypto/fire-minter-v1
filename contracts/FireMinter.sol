// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./FireToken.sol";
import "./lib/Ownable.sol";

contract FireMinterV1 is Ownable {
    mapping(address => address[]) public getTokens;

    mapping(address => bool) public isFireToken;

    address[] public allTokens;

    event TokenCreated(address indexed token, address indexed owner);

    uint256 public fee = 1 ether;

    uint256 public totalFees;

    uint8 public maxTaxFee = 10;

    uint8 public maxLiquidityFee = 10;

    uint8 public maxFundFee = 3;

    uint256 public minimumStartingLiquidty = 1 ether;

    function getAllTokensLength() external view returns (uint256) {
        return allTokens.length;
    }

    function setFee(uint256 _fee) external onlyOwner() {
        fee = _fee;
    }

    function _pay(address payable _address, uint256 _amount) private {
        (bool success, ) = _address.call{value: _amount}("");
        require(
            success,
            "Address: unable to send value, recipient may have reverted"
        );
    }

    function withdraw() external onlyOwner() {
        _pay(payable(owner()), address(this).balance);
    }

    function setMaxTaxFee(uint8 _amount) external onlyOwner() {
        maxTaxFee = _amount;
    }

    function setMaxLiquidityFee(uint8 _amount) external onlyOwner() {
        maxLiquidityFee = _amount;
    }

    function setMaxFundFee(uint8 _amount) external onlyOwner() {
        maxFundFee = _amount;
    }

    function setMinimumStartingLiquidity(uint256 _amount) external onlyOwner() {
        minimumStartingLiquidty = _amount;
    }

    modifier createTokenGuard(
        Token memory _token,
        uint256 _initialLiquidityAmount
    ) {
        require(
            _token.taxFee <= maxTaxFee,
            "The tax fee is too high. Please choose a value lower than the max tax fee."
        );
        require(
            _token.liquidityFee <= maxLiquidityFee,
            "The liquidity fee is too high. Please choose a value lower than the max liquidity fee."
        );
        require(
            _token.fundFee <= maxFundFee,
            "The fund fee is too high. Please choose a value lower than the max fund fee."
        );
        require(
            _token.supply > _token.maxTxAmount,
            "Token supply must be larger than the maximum amount per tx"
        );
        require(
            _token.supply > _token.numberTokensSellToAddToLiquidity,
            "Token supply must be larger than the number of tokens to be added to the liquidity"
        );
        require(
            msg.value > fee + minimumStartingLiquidty,
            "Need to pay a fee and have enough for the minimum starting liquidity to create a token"
        );
        require(
            _initialLiquidityAmount > 0 &&
                _token.supply > _initialLiquidityAmount,
            "You need to provide initial liquidity and needs to be lower than token total supply"
        );
        _;
    }

    function createToken(
        Token memory _token,
        address _newOwner,
        address _fund,
        uint256 _initialLiquidityAmount
    )
        external
        payable
        createTokenGuard(_token, _initialLiquidityAmount)
        returns (address)
    {
        FireToken token = new FireToken(
            _token,
            _initialLiquidityAmount,
            _newOwner,
            _fund
        );

        _pay(payable(token), msg.value - fee);

        token.initialize();

        token.transferOwnership(_newOwner);

        getTokens[_newOwner].push(address(token));
        allTokens.push(address(token));
        totalFees += fee;
        emit TokenCreated(address(token), _newOwner);
        return address(this);
    }
}
