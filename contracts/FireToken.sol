// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./lib/Ownable.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IERC20MetaData.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Factory.sol";

struct Token {
    bytes32 name;
    bytes32 symbol;
    uint8 decimals;
    uint256 supply;
    uint256 reflectionSupply;
    uint256 totalTokenFees;
    uint8 taxFee;
    uint8 liquidityFee;
    uint8 fundFee;
    uint256 maxTxAmount;
    uint256 numberTokensSellToAddToLiquidity;
}

contract FireToken is IERC20, IERC20Metadata, Ownable {
    Token token;

    event SwapAndLiquefy(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );
    event SwapAndLiquefyStateUpdate(bool state);

    mapping(address => uint256) private _reflectionBalance;

    mapping(address => bool) private _isExcludedFromFees;

    mapping(address => mapping(address => uint256)) private _allowances;

    bool public isSwapAndLiquifyingEnabled;

    bool private _swapAndLiquifyingInProgress;

    bool public startTrading;

    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable uniswapV2WETHPair;

    address public immutable fund;

    uint8 private _prevFundFee;
    uint8 private _prevTaxFee;
    uint8 private _prevLiquidityFee;

    uint256 initialLiquidityAmount;
    bool onlyOnce;

    constructor(
        Token memory _token,
        uint256 _initialLiquidityAmount,
        address _newOwner,
        address _fund
    ) {
        uint256 MAX_INT_VALUE = type(uint256).max;

        token.name = _token.name;
        token.symbol = _token.symbol;
        token.decimals = _token.decimals;
        token.supply = _token.supply;
        token.reflectionSupply = (MAX_INT_VALUE -
            (MAX_INT_VALUE % _token.supply));
        token.taxFee = _token.taxFee;
        token.maxTxAmount = _token.maxTxAmount;
        token.numberTokensSellToAddToLiquidity = _token
        .numberTokensSellToAddToLiquidity;
        token.liquidityFee = _token.liquidityFee;
        token.fundFee = _token.fundFee;

        _reflectionBalance[_newOwner] =
            token.reflectionSupply -
            _reflectionFromToken(_initialLiquidityAmount);
        _reflectionBalance[address(this)] = _reflectionFromToken(
            _initialLiquidityAmount
        );

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
            0x10ED43C718714eb63d5aA57B78B54704E256024E
        );

        uniswapV2WETHPair = IUniswapV2Factory(_uniswapV2Router.factory())
        .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;

        fund = _fund;

        initialLiquidityAmount = _initialLiquidityAmount;

        _isExcludedFromFees[_newOwner] = true;
        _isExcludedFromFees[address(this)] = true;
        _isExcludedFromFees[_fund] = true;

        emit Transfer(address(0), _newOwner, _token.supply);
    }

    function initialize() external {
        assert(!onlyOnce);
        onlyOnce = true;
        _addLiquidity(initialLiquidityAmount, address(this).balance);
    }

    function name() public view override returns (bytes32) {
        return token.name;
    }

    function symbol() public view override returns (bytes32) {
        return token.symbol;
    }

    function decimals() public view override returns (uint8) {
        return token.decimals;
    }

    modifier lockTheSwap {
        _swapAndLiquifyingInProgress = true;
        _;
        _swapAndLiquifyingInProgress = false;
    }

    function totalSupply() external view override returns (uint256) {
        return token.supply;
    }

    function _getRate() private view returns (uint256) {
        return token.reflectionSupply / token.supply;
    }

    function _reflectionFromToken(uint256 amount)
        private
        view
        returns (uint256)
    {
        require(
            token.supply >= amount,
            "You cannot own more tokens than the total token supply"
        );
        return amount * _getRate();
    }

    function _tokenFromReflection(uint256 reflectionAmount)
        private
        view
        returns (uint256)
    {
        require(
            token.reflectionSupply >= reflectionAmount,
            "Cannot have a personal reflection amount larger than total reflection"
        );
        return reflectionAmount / _getRate();
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _tokenFromReflection(_reflectionBalance[account]);
    }

    function totalFees() external view returns (uint256) {
        return token.totalTokenFees;
    }

    function deliver(uint256 amount) public {
        address sender = _msgSender();
        uint256 reflectionAmount = _reflectionFromToken(amount);
        _reflectionBalance[sender] =
            _reflectionBalance[sender] -
            reflectionAmount;
        token.reflectionSupply -= reflectionAmount;
        token.totalTokenFees += amount;
    }

    function _removeAllFees() private {
        if (token.taxFee == 0 && token.liquidityFee == 0 && token.fundFee == 0)
            return;

        _prevFundFee = token.fundFee;
        _prevLiquidityFee = token.liquidityFee;
        _prevTaxFee = token.taxFee;

        token.taxFee = 0;
        token.liquidityFee = 0;
        token.fundFee = 0;
    }

    function _restoreAllFees() private {
        token.taxFee = _prevTaxFee;
        token.liquidityFee = _prevLiquidityFee;
        token.fundFee = _prevFundFee;
    }

    function enableSwapAndLiquifyingState() external onlyOwner() {
        isSwapAndLiquifyingEnabled = true;
        emit SwapAndLiquefyStateUpdate(true);
    }

    function _calculateFee(uint256 amount, uint8 fee)
        private
        pure
        returns (uint256)
    {
        return (amount * fee) / 100;
    }

    function _calculateTaxFee(uint256 amount) private view returns (uint256) {
        return _calculateFee(amount, token.taxFee);
    }

    function _calculateLiquidityFee(uint256 amount)
        private
        view
        returns (uint256)
    {
        return _calculateFee(amount, token.liquidityFee);
    }

    function _calculateFundFee(uint256 amount) private view returns (uint256) {
        return _calculateFee(amount, token.fundFee);
    }

    function _reflectFee(uint256 rfee, uint256 fee) private {
        token.reflectionSupply -= rfee;
        token.totalTokenFees += fee;
    }

    function _takeLiquidity(uint256 amount) private {
        _reflectionBalance[address(this)] =
            _reflectionBalance[address(this)] +
            _reflectionFromToken(amount);
    }

    receive() external payable {}

    function _transferToken(
        address sender,
        address recipient,
        uint256 amount,
        bool removeFees
    ) private {
        if (removeFees) _removeAllFees();

        uint256 rAmount = _reflectionFromToken(amount);

        _reflectionBalance[sender] = _reflectionBalance[sender] - rAmount;

        uint256 rTax = _reflectionFromToken(_calculateTaxFee(amount));

        uint256 rFundTax = _reflectionFromToken(_calculateFundFee(amount));

        uint256 rLiquidityTax = _reflectionFromToken(
            _calculateLiquidityFee(amount)
        );

        _reflectionBalance[recipient] =
            _reflectionBalance[recipient] +
            rAmount -
            rTax -
            rFundTax -
            rLiquidityTax;

        _reflectionBalance[fund] = _reflectionBalance[fund] + rFundTax;

        _takeLiquidity(rLiquidityTax);
        _reflectFee(
            rTax,
            _calculateTaxFee(amount) +
                _calculateFundFee(amount) +
                _calculateLiquidityFee(amount)
        );

        emit Transfer(
            sender,
            recipient,
            amount -
                _calculateLiquidityFee(amount) -
                _calculateFundFee(amount) -
                _calculateTaxFee(amount)
        );

        // Restores all fees if they were disabled.
        if (removeFees) _restoreAllFees();
    }

    function _swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function _addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(0),
            block.timestamp
        );
    }

    function _swapAndLiquefy() private lockTheSwap() {
        // split the contract token balance into halves
        uint256 half = token.numberTokensSellToAddToLiquidity / 2;
        uint256 otherHalf = token.numberTokensSellToAddToLiquidity - half;

        uint256 initialETHContractBalance = address(this).balance;

        // Buys ETH at current token price
        _swapTokensForEth(half);

        // This is to make sure we are only using ETH derived from the liquidity fee
        uint256 ethBought = address(this).balance - initialETHContractBalance;

        // Add liquidity to the pool
        _addLiquidity(otherHalf, ethBought);

        emit SwapAndLiquefy(half, ethBought, otherHalf);
    }

    function enableTrading() external onlyOwner() {
        startTrading = true;
    }

    function isExcludedFromFees(address account) external view returns (bool) {
        return _isExcludedFromFees[account];
    }

    function excludeFromFees(address account) external onlyOwner() {
        _isExcludedFromFees[account] = true;
    }

    function includeInFees(address account) external onlyOwner() {
        _isExcludedFromFees[account] = false;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        require(
            sender != address(0),
            "ERC20: Sender cannot be the zero address"
        );
        require(
            recipient != address(0),
            "ERC20: Recipient cannot be the zero address"
        );
        require(amount > 0, "Transfer amount must be greater than zero");
        if (sender != owner() && recipient != owner()) {
            require(
                amount <= token.maxTxAmount,
                "Transfer amount exceeds the maxTxAmount."
            );

            require(startTrading, "Nice try :)");
        }

        // Condition 1: Make sure the contract has the enough tokens to liquefy
        // Condition 2: We are not in a liquefication event
        // Condition 3: Liquification is enabled
        // Condition 4: It is not the uniswapPair that is sending tokens

        if (
            balanceOf(address(this)) >=
            token.numberTokensSellToAddToLiquidity &&
            !_swapAndLiquifyingInProgress &&
            isSwapAndLiquifyingEnabled &&
            sender != address(uniswapV2WETHPair)
        ) _swapAndLiquefy();

        _transferToken(
            sender,
            recipient,
            amount,
            _isExcludedFromFees[sender] || _isExcludedFromFees[recipient]
        );
    }

    function _approve(
        address owner,
        address beneficiary,
        uint256 amount
    ) private {
        require(
            beneficiary != address(0),
            "The burn address is not allowed to receive approval for allowances."
        );
        require(
            owner != address(0),
            "The burn address is not allowed to approve allowances."
        );

        _allowances[owner][beneficiary] = amount;
        emit Approval(owner, beneficiary, amount);
    }

    function transfer(address recipient, uint256 amount)
        external
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function approve(address beneficiary, uint256 amount)
        external
        override
        returns (bool)
    {
        _approve(_msgSender(), beneficiary, amount);
        return true;
    }

    function transferFrom(
        address provider,
        address beneficiary,
        uint256 amount
    ) external override returns (bool) {
        _transfer(provider, beneficiary, amount);
        _approve(
            provider,
            _msgSender(),
            _allowances[provider][_msgSender()] - amount
        );
        return true;
    }

    function allowance(address owner, address beneficiary)
        external
        view
        override
        returns (uint256)
    {
        return _allowances[owner][beneficiary];
    }

    function increaseAllowance(address beneficiary, uint256 amount)
        external
        returns (bool)
    {
        _approve(
            _msgSender(),
            beneficiary,
            _allowances[_msgSender()][beneficiary] + amount
        );
        return true;
    }

    function decreaseAllowance(address beneficiary, uint256 amount)
        external
        returns (bool)
    {
        _approve(
            _msgSender(),
            beneficiary,
            _allowances[_msgSender()][beneficiary] - amount
        );
        return true;
    }
}
