/**

 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.4;



import "./safetoken-imports.sol";

abstract contract Tokenomics {
    
    using SafeMath for uint256;
    


    string internal constant NAME = "SafeToken.V1Beta";
    string internal constant SYMBOL = "STKN.V1Beta";
    
    uint16 internal constant FEES_DIVISOR = 10**3;
    uint8 internal constant DECIMALS = 6;
    uint256 internal constant ZEROES = 10**DECIMALS;
    
    uint256 private constant MAX = ~uint256(0);
    uint256 internal constant TOTAL_SUPPLY = 299792458 * ZEROES;
    uint256 internal _reflectedSupply = (MAX - (MAX % TOTAL_SUPPLY));

    uint256 internal constant maxTransactionAmount = TOTAL_SUPPLY / 100; // 1% of the total supply
    

    uint256 internal constant maxWalletBalance = TOTAL_SUPPLY / 50; // 2% of the total supply
    

    uint256 internal constant numberOfTokensToSwapToLiquidity = TOTAL_SUPPLY / 1000; // 0.1% of the total supply


    address internal charityAddress ;
    address internal marketingAddress ;

    address internal burnAddress = 0x000000000000000000000000000000000000dEaD;

 
    address internal tipToTheDev = 0xe6708d1352e0a09Af0E43F3a89d9BE9E01734eE4;

    enum FeeType { Antiwhale, Burn, Liquidity, Rfi, External, ExternalToETH }
    struct Fee {
        FeeType name;
        uint256 value;
        address recipient;
        uint256 total;
    }

    Fee[] internal fees;
    uint256 internal sumOfFees;

    constructor() {
        _addFees();
    }

    function _addFee(FeeType name, uint256 value, address recipient) private {
        fees.push( Fee(name, value, recipient, 0 ) );
        sumOfFees += value;
    }

    function _addFees() private {
 
        _addFee(FeeType.Rfi, 40, address(this) ); 

        _addFee(FeeType.Burn, 10, burnAddress );
        _addFee(FeeType.Liquidity, 50, address(this) );
        _addFee(FeeType.External, 20, charityAddress );
        _addFee(FeeType.External, 30, marketingAddress );

        // 0.1% as a tip to the dev; feel free to remove this!
        _addFee(FeeType.ExternalToETH, 1, tipToTheDev );
    }

    function _getFeesCount() internal view returns (uint256){ return fees.length; }

    function _getFeeStruct(uint256 index) private view returns(Fee storage){
        require( index >= 0 && index < fees.length, "FeesSettings._getFeeStruct: Fee index out of bounds");
        return fees[index];
    }
    function _getFee(uint256 index) internal view returns (FeeType, uint256, address, uint256){
        Fee memory fee = _getFeeStruct(index);
        return ( fee.name, fee.value, fee.recipient, fee.total );
    }
    function _addFeeCollectedAmount(uint256 index, uint256 amount) internal {
        Fee storage fee = _getFeeStruct(index);
        fee.total = fee.total.add(amount);
    }

    // function getCollectedFeeTotal(uint256 index) external view returns (uint256){
    function getCollectedFeeTotal(uint256 index) internal view returns (uint256){
        Fee memory fee = _getFeeStruct(index);
        return fee.total;
    }
}

abstract contract Presaleable is Manageable {
    bool internal isInPresale;
    function setPreseableEnabled(bool value) external onlyManager {
        isInPresale = value;
    }
}

abstract contract BaseRfiToken is IERC20, IERC20Metadata, Ownable, Presaleable, Tokenomics {

    using SafeMath for uint256;
    using Address for address;

    mapping (address => uint256) internal _reflectedBalances;
    mapping (address => uint256) internal _balances;
    mapping (address => mapping (address => uint256)) internal _allowances;
    
    mapping (address => bool) internal _isExcludedFromFee;
    mapping (address => bool) internal _isExcludedFromRewards;
    address[] private _excluded;
    
    constructor(){
        
        _reflectedBalances[owner()] = _reflectedSupply;
        
        // exclude owner and this contract from fee
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        
        // exclude the owner and this contract from rewards
        _exclude(owner());
        _exclude(address(this));

        emit Transfer(address(0), owner(), TOTAL_SUPPLY);
        
    }
    

        function totalSupply() external pure override returns (uint256) {
            return TOTAL_SUPPLY;
        }
        
        function balanceOf(address account) public view override returns (uint256){
            if (_isExcludedFromRewards[account]) return _balances[account];
            return tokenFromReflection(_reflectedBalances[account]);
        }
        
        function transfer(address recipient, uint256 amount) external override returns (bool){
            _transfer(_msgSender(), recipient, amount);
            return true;
        }
        
        function allowance(address owner, address spender) external view override returns (uint256){
            return _allowances[owner][spender];
        }
    
        function approve(address spender, uint256 amount) external override returns (bool) {
            _approve(_msgSender(), spender, amount);
            return true;
        }
        
        function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool){
            _transfer(sender, recipient, amount);
            _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
            return true;
        }

    function burn(uint256 amount) external {

        address sender = _msgSender();
        require(sender != address(0), "BaseRfiToken: burn from the zero address");
        require(sender != address(burnAddress), "BaseRfiToken: burn from the burn address");

        uint256 balance = balanceOf(sender);
        require(balance >= amount, "BaseRfiToken: burn amount exceeds balance");

        uint256 reflectedAmount = amount.mul(_getCurrentRate());

        // remove the amount from the sender's balance first
        _reflectedBalances[sender] = _reflectedBalances[sender].sub(reflectedAmount);
        if (_isExcludedFromRewards[sender])
            _balances[sender] = _balances[sender].sub(amount);

        _burnTokens( sender, amount, reflectedAmount );
    }
    
    /**
     * @dev "Soft" burns the specified amount of tokens by sending them 
     * to the burn address
     */
    function _burnTokens(address sender, uint256 tBurn, uint256 rBurn) internal {

        emit Transfer(sender, burnAddress, tBurn);
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }
    
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }
    
    function isExcludedFromReward(address account) external view returns (bool) {
        return _isExcludedFromRewards[account];
    }

 
    function reflectionFromToken(uint256 tAmount, bool deductTransferFee) external view returns(uint256) {
        require(tAmount <= TOTAL_SUPPLY, "Amount must be less than supply");
        if (!deductTransferFee) {
            (uint256 rAmount,,,,) = _getValues(tAmount,0);
            return rAmount;
        } else {
            (,uint256 rTransferAmount,,,) = _getValues(tAmount,_getSumOfFees(_msgSender(), tAmount));
            return rTransferAmount;
        }
    }


    function tokenFromReflection(uint256 rAmount) internal view returns(uint256) {
        require(rAmount <= _reflectedSupply, "Amount must be less than total reflections");
        uint256 currentRate = _getCurrentRate();
        return rAmount.div(currentRate);
    }
    
    function excludeFromReward(address account) external onlyOwner() {
        require(!_isExcludedFromRewards[account], "Account is not included");
        _exclude(account);
    }
    
    function _exclude(address account) internal {
        if(_reflectedBalances[account] > 0) {
            _balances[account] = tokenFromReflection(_reflectedBalances[account]);
        }
        _isExcludedFromRewards[account] = true;
        _excluded.push(account);
    }

    function includeInReward(address account) external onlyOwner() {
        require(_isExcludedFromRewards[account], "Account is not excluded");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _balances[account] = 0;
                _isExcludedFromRewards[account] = false;
                _excluded.pop();
                break;
            }
        }
    }
    
    function setExcludedFromFee(address account, bool value) external onlyOwner { _isExcludedFromFee[account] = value; }
    function isExcludedFromFee(address account) public view returns(bool) { return _isExcludedFromFee[account]; }
    
    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "BaseRfiToken: approve from the zero address");
        require(spender != address(0), "BaseRfiToken: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
    
    /**
     */
    function _isUnlimitedSender(address account) internal view returns(bool){
        // the owner should be the only whitelisted sender
        return (account == owner());
    }
    /**
     */
    function _isUnlimitedRecipient(address account) internal view returns(bool){
        // the owner should be a white-listed recipient
        // and anyone should be able to burn as many tokens as 
        // he/she wants
        return (account == owner() || account == burnAddress);
    }

    function _transfer(address sender, address recipient, uint256 amount) private {
        require(sender != address(0), "BaseRfiToken: transfer from the zero address");
        require(recipient != address(0), "BaseRfiToken: transfer to the zero address");
        require(sender != address(burnAddress), "BaseRfiToken: transfer from the burn address");
        require(amount > 0, "Transfer amount must be greater than zero");
        
        // indicates whether or not feee should be deducted from the transfer
        bool takeFee = true;

        if ( isInPresale ){ takeFee = false; }
        else {
            /**
            * Check the amount is within the max allowed limit as long as a
            * unlimited sender/recepient is not involved in the transaction
            */
            if ( amount > maxTransactionAmount && !_isUnlimitedSender(sender) && !_isUnlimitedRecipient(recipient) ){
                revert("Transfer amount exceeds the maxTxAmount.");
            }
            /**
            * The pair needs to excluded from the max wallet balance check; 
            * selling tokens is sending them back to the pair (without this
            * check, selling tokens would not work if the pair's balance 
            * was over the allowed max)
            *
            * Note: This does NOT take into account the fees which will be deducted 
            *       from the amount. As such it could be a bit confusing 
            */
            if ( maxWalletBalance > 0 && !_isUnlimitedSender(sender) && !_isUnlimitedRecipient(recipient) && !_isV2Pair(recipient) ){
                uint256 recipientBalance = balanceOf(recipient);
                require(recipientBalance + amount <= maxWalletBalance, "New balance would exceed the maxWalletBalance");
            }
        }

        // if any account belongs to _isExcludedFromFee account then remove the fee
        if(_isExcludedFromFee[sender] || _isExcludedFromFee[recipient]){ takeFee = false; }

        _beforeTokenTransfer(sender, recipient, amount, takeFee);
        _transferTokens(sender, recipient, amount, takeFee);
        
    }

    function _transferTokens(address sender, address recipient, uint256 amount, bool takeFee) private {
    
   
        uint256 sumOfFees = _getSumOfFees(sender, amount);
        if ( !takeFee ){ sumOfFees = 0; }
        
        (uint256 rAmount, uint256 rTransferAmount, uint256 tAmount, uint256 tTransferAmount, uint256 currentRate ) = _getValues(amount, sumOfFees);
        
  
        _reflectedBalances[sender] = _reflectedBalances[sender].sub(rAmount);
        _reflectedBalances[recipient] = _reflectedBalances[recipient].add(rTransferAmount);

       
        if (_isExcludedFromRewards[sender]){ _balances[sender] = _balances[sender].sub(tAmount); }
        if (_isExcludedFromRewards[recipient] ){ _balances[recipient] = _balances[recipient].add(tTransferAmount); }
        
        _takeFees( amount, currentRate, sumOfFees );
        emit Transfer(sender, recipient, tTransferAmount);
    }
    
    function _takeFees(uint256 amount, uint256 currentRate, uint256 sumOfFees ) private {
        if ( sumOfFees > 0 && !isInPresale ){
            _takeTransactionFees(amount, currentRate);
        }
    }
    
    function _getValues(uint256 tAmount, uint256 feesSum) internal view returns (uint256, uint256, uint256, uint256, uint256) {
        
        uint256 tTotalFees = tAmount.mul(feesSum).div(FEES_DIVISOR);
        uint256 tTransferAmount = tAmount.sub(tTotalFees);
        uint256 currentRate = _getCurrentRate();
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rTotalFees = tTotalFees.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rTotalFees);
        
        return (rAmount, rTransferAmount, tAmount, tTransferAmount, currentRate);
    }
    
    function _getCurrentRate() internal view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }
    
    function _getCurrentSupply() internal view returns(uint256, uint256) {
        uint256 rSupply = _reflectedSupply;
        uint256 tSupply = TOTAL_SUPPLY;  

        /**
         * The code below removes balances of addresses excluded from rewards from
         * rSupply and tSupply, which effectively increases the % of transaction fees
         * delivered to non-excluded holders
         */    
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_reflectedBalances[_excluded[i]] > rSupply || _balances[_excluded[i]] > tSupply) return (_reflectedSupply, TOTAL_SUPPLY);
            rSupply = rSupply.sub(_reflectedBalances[_excluded[i]]);
            tSupply = tSupply.sub(_balances[_excluded[i]]);
        }
        if (tSupply == 0 || rSupply < _reflectedSupply.div(TOTAL_SUPPLY)) return (_reflectedSupply, TOTAL_SUPPLY);
        return (rSupply, tSupply);
    }
    
 
    function _beforeTokenTransfer(address sender, address recipient, uint256 amount, bool takeFee) internal virtual;

    function _getSumOfFees(address sender, uint256 amount) internal view virtual returns (uint256);

    function _isV2Pair(address account) internal view virtual returns(bool);


    function _redistribute(uint256 amount, uint256 currentRate, uint256 fee, uint256 index) internal {
        uint256 tFee = amount.mul(fee).div(FEES_DIVISOR);
        uint256 rFee = tFee.mul(currentRate);

        _reflectedSupply = _reflectedSupply.sub(rFee);
        _addFeeCollectedAmount(index, tFee);
    }


    function _takeTransactionFees(uint256 amount, uint256 currentRate) internal virtual;
}

abstract contract Liquifier is Ownable, Manageable {

    using SafeMath for uint256;

    uint256 private withdrawableBalance;

    enum Env {Testnet, MainnetV1, MainnetV2}
    Env private _env;

    // PancakeSwap V1
    address private _mainnetRouterV1Address = 0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F;
    // PancakeSwap V2
    address private _mainnetRouterV2Address = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    // Testnet
    // address private _testnetRouterAddress = 0xD99D1c33F9fC3444f8101754aBC46c52416550D1;
    // PancakeSwap Testnet = https://pancake.kiemtienonline360.com/
    address private _testnetRouterAddress = 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3;

    IPancakeV2Router internal _router;
    address internal _pair;
    
    bool private inSwapAndLiquify;
    bool private swapAndLiquifyEnabled = true;

    uint256 private maxTransactionAmount;
    uint256 private numberOfTokensToSwapToLiquidity;

    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    event RouterSet(address indexed router);
    event SwapAndLiquify(uint256 tokensSwapped, uint256 ethReceived, uint256 tokensIntoLiquidity);
    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event LiquidityAdded(uint256 tokenAmountSent, uint256 ethAmountSent, uint256 liquidity);

    receive() external payable {}

    function initializeLiquiditySwapper(Env env, uint256 maxTx, uint256 liquifyAmount) internal {
        _env = env;
        if (_env == Env.MainnetV1){ _setRouterAddress(_mainnetRouterV1Address); }
        else if (_env == Env.MainnetV2){ _setRouterAddress(_mainnetRouterV2Address); }
        else /*(_env == Env.Testnet)*/{ _setRouterAddress(_testnetRouterAddress); }

        maxTransactionAmount = maxTx;
        numberOfTokensToSwapToLiquidity = liquifyAmount;

    }

  
    function liquify(uint256 contractTokenBalance, address sender) internal {

        if (contractTokenBalance >= maxTransactionAmount) contractTokenBalance = maxTransactionAmount;
        
        bool isOverRequiredTokenBalance = ( contractTokenBalance >= numberOfTokensToSwapToLiquidity );
        
        /**
         * - first check if the contract has collected enough tokens to swap and liquify
         * - then check swap and liquify is enabled
         * - then make sure not to get caught in a circular liquidity event
         * - finally, don't swap & liquify if the sender is the uniswap pair
         */
        if ( isOverRequiredTokenBalance && swapAndLiquifyEnabled && !inSwapAndLiquify && (sender != _pair) ){
            // TODO check if the `(sender != _pair)` is necessary because that basically
            // stops swap and liquify for all "buy" transactions
            _swapAndLiquify(contractTokenBalance);            
        }

    }

  
    function _setRouterAddress(address router) private {
        IPancakeV2Router _newPancakeRouter = IPancakeV2Router(router);
        _pair = IPancakeV2Factory(_newPancakeRouter.factory()).createPair(address(this), _newPancakeRouter.WETH());
        _router = _newPancakeRouter;
        emit RouterSet(router);
    }
    
    function _swapAndLiquify(uint256 amount) private lockTheSwap {
        
        // split the contract balance into halves
        uint256 half = amount.div(2);
        uint256 otherHalf = amount.sub(half);
        
        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;
        
        // swap tokens for ETH
        _swapTokensForEth(half); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // add liquidity to uniswap
        _addLiquidity(otherHalf, newBalance);
        
        emit SwapAndLiquify(half, newBalance, otherHalf);
    }
    
    function _swapTokensForEth(uint256 tokenAmount) private {
        
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _router.WETH();

        _approveDelegate(address(this), address(_router), tokenAmount);

        // make the swap
        _router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            // The minimum amount of output tokens that must be received for the transaction not to revert.
            // 0 = accept any amount (slippage is inevitable)
            0,
            path,
            address(this),
            block.timestamp
        );
    }
    
    function _addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approveDelegate(address(this), address(_router), tokenAmount);

        // add tahe liquidity
        (uint256 tokenAmountSent, uint256 ethAmountSent, uint256 liquidity) = _router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            // Bounds the extent to which the WETH/token price can go up before the transaction reverts. 
            // Must be <= amountTokenDesired; 0 = accept any amount (slippage is inevitable)
            0,
            // Bounds the extent to which the token/WETH price can go up before the transaction reverts.
            // 0 = accept any amount (slippage is inevitable)
            0,
            // this is a centralized risk if the owner's account is ever compromised (see Certik SSL-04)
            owner(),
            block.timestamp
        );

  
        withdrawableBalance = address(this).balance;
        emit LiquidityAdded(tokenAmountSent, ethAmountSent, liquidity);
    }
    

 
    function setRouterAddress(address router) external onlyManager() {
        _setRouterAddress(router);
    }

 
    function setSwapAndLiquifyEnabled(bool enabled) external onlyManager {
        swapAndLiquifyEnabled = enabled;
        emit SwapAndLiquifyEnabledUpdated(swapAndLiquifyEnabled);
    }


    function withdrawLockedEth(address payable recipient) external onlyManager(){
        require(recipient != address(0), "Cannot withdraw the ETH balance to the zero address");
        require(withdrawableBalance > 0, "The ETH balance must be greater than 0");

        // prevent re-entrancy attacks
        uint256 amount = withdrawableBalance;
        withdrawableBalance = 0;
        recipient.transfer(amount);
    }


    function _approveDelegate(address owner, address spender, uint256 amount) internal virtual;

}



abstract contract SafeToken is BaseRfiToken, Liquifier, Antiwhale {
    
    using SafeMath for uint256;

    // constructor(string memory _name, string memory _symbol, uint8 _decimals){
    constructor(Env _env){

        initializeLiquiditySwapper(_env, maxTransactionAmount, numberOfTokensToSwapToLiquidity);

        // exclude the pair address from rewards - we don't want to redistribute
        // tx fees to these two; redistribution is only for holders, dah!
        _exclude(_pair);
        _exclude(burnAddress);
    }
    
    function _isV2Pair(address account) internal view override returns(bool){
        return (account == _pair);
    }

    function _getSumOfFees(address sender, uint256 amount) internal view override returns (uint256){ 
        return _getAntiwhaleFees(balanceOf(sender), amount); 
    }
    
    // function _beforeTokenTransfer(address sender, address recipient, uint256 amount, bool takeFee) internal override {
    function _beforeTokenTransfer(address sender, address , uint256 , bool ) internal override {
        if ( !isInPresale ){
            uint256 contractTokenBalance = balanceOf(address(this));
            liquify( contractTokenBalance, sender );
        }
    }

    function _takeTransactionFees(uint256 amount, uint256 currentRate) internal override {
        
        if( isInPresale ){ return; }

        uint256 feesCount = _getFeesCount();
        for (uint256 index = 0; index < feesCount; index++ ){
            (FeeType name, uint256 value, address recipient,) = _getFee(index);
            // no need to check value < 0 as the value is uint (i.e. from 0 to 2^256-1)
            if ( value == 0 ) continue;

            if ( name == FeeType.Rfi ){
                _redistribute( amount, currentRate, value, index );
            }
            else if ( name == FeeType.Burn ){
                _burn( amount, currentRate, value, index );
            }
            else if ( name == FeeType.Antiwhale){
                // TODO
            }
            else if ( name == FeeType.ExternalToETH){
                _takeFeeToETH( amount, currentRate, value, recipient, index );
            }
            else {
                _takeFee( amount, currentRate, value, recipient, index );
            }
        }
    }

    function _burn(uint256 amount, uint256 currentRate, uint256 fee, uint256 index) private {
        uint256 tBurn = amount.mul(fee).div(FEES_DIVISOR);
        uint256 rBurn = tBurn.mul(currentRate);

        _burnTokens(address(this), tBurn, rBurn);
        _addFeeCollectedAmount(index, tBurn);
    }

    function _takeFee(uint256 amount, uint256 currentRate, uint256 fee, address recipient, uint256 index) private {

        uint256 tAmount = amount.mul(fee).div(FEES_DIVISOR);
        uint256 rAmount = tAmount.mul(currentRate);

        _reflectedBalances[recipient] = _reflectedBalances[recipient].add(rAmount);
        if(_isExcludedFromRewards[recipient])
            _balances[recipient] = _balances[recipient].add(tAmount);

        _addFeeCollectedAmount(index, tAmount);
    }
    
 
    function _takeFeeToETH(uint256 amount, uint256 currentRate, uint256 fee, address recipient, uint256 index) private {
        _takeFee(amount, currentRate, fee, recipient, index);        
    }

    function _approveDelegate(address owner, address spender, uint256 amount) internal override {
        _approve(owner, spender, amount);
    }
}

contract SafeTokenV1Beta is SafeToken{

    constructor() SafeToken(Env.Testnet){
        // pre-approve the initial liquidity supply (to safe a bit of time)
        _approve(owner(),address(_router), ~uint256(0));
    }
}
