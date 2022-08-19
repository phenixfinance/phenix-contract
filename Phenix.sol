pragma solidity ^0.7.4;

// SPDX-License-Identifier: MIT

import "./ERC20Detailed.sol";
import "./IVVSFactory.sol";
import "./IVVSRouter.sol";
import "./ERC20Detailed.sol";
import "./ERC20Detailed.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./SafeMathInt.sol";
import "./InterfaceLP.sol";
import "./TokenVesting.sol";

contract Phenix is ERC20Detailed, Ownable {
    using SafeMath for uint256;
    using SafeMathInt for int256;

    event Rebase(uint256 indexed totalSupply);

    InterfaceLP public pairContract;
    address public liquidityReceiver;
    address public phenixFundReserveReciever;
    bool public initialDistributionFinished;
    bool public autoRebaseState;

    PhenixTokenVesting private phenixVestingContract;

    mapping(address => bool) _allowTransfer;
    mapping(address => bool) _isFeeExempt;

    uint256 private constant DECIMALS = 18;
    uint256 private constant MAX_UINT256 = ~uint256(0);
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address private constant ZERO = 0x0000000000000000000000000000000000000000;
    uint256 private constant REBASE_SCALING_VALUE = 100000;
    uint256 private constant REBASE_INTERVAL = 86400;
    uint256 private constant INITIAL_FRAGMENTS_SUPPLY =
        1 * 10**9 * 10**DECIMALS;

    uint256 public liquidityFee = 5;
    uint256 public phenixVaultFee = 8;
    uint256 public sellFee = 2;
    uint256 public totalFee = liquidityFee.add(phenixVaultFee);
    uint256 public feeDenominator = 100;

    uint256 public lastRebaseTimestamp = block.timestamp;
    uint256 public lastRebaseDelta = 0;
    uint256 public rebasePercentDelta = 18; // 1.8 percent
    uint256 public rebaseDenominator = 1000;
    uint256 public minimumRebaseTimestampDelta = 60;

    uint256 targetLiquidity = 50;
    uint256 targetLiquidityDenominator = 100;

    IVVSRouter public router;
    address public pair;

    bool public swapEnabled = true;
    uint256 private gonSwapThreshold = (TOTAL_GONS * 10) / 10000;
    bool inSwap;

    uint256 private constant TOTAL_GONS =
        MAX_UINT256 - (MAX_UINT256 % INITIAL_FRAGMENTS_SUPPLY);
    uint256 private constant MAX_SUPPLY = ~uint128(0);
    uint256 private _totalSupply;
    uint256 private _gonsPerFragment;
    mapping(address => uint256) private _gonBalances;
    mapping(address => mapping(address => uint256)) private _allowedFragments;
    mapping(address => bool) public _taxableAddress;

    constructor() ERC20Detailed("Phenix", "PHNX", uint8(DECIMALS)) {
        router = IVVSRouter(0x145677FC4d9b8F19B5D56d1820c48e0443049a30);

        pair = IVVSFactory(router.factory()).createPair(
            router.WETH(),
            address(this)
        );

        phenixVestingContract = new PhenixTokenVesting(
            address(this),
            address(pair),
            address(msg.sender)
        );

        liquidityReceiver = address(phenixVestingContract);
        phenixFundReserveReciever = address(phenixVestingContract);

        _allowedFragments[address(this)][address(router)] = uint256(-1);
        pairContract = InterfaceLP(pair);

        _totalSupply = INITIAL_FRAGMENTS_SUPPLY;
        _gonBalances[address(phenixVestingContract)] = TOTAL_GONS;
        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);

        initialDistributionFinished = false;
        autoRebaseState = false;

        _isFeeExempt[address(phenixFundReserveReciever)] = true;
        _isFeeExempt[address(phenixVestingContract)] = true;
        _isFeeExempt[address(this)] = true;
        _isFeeExempt[address(msg.sender)] = true;

        _allowTransfer[address(phenixVestingContract)] = true;

        _taxableAddress[address(pair)] = true;

        emit Transfer(
            address(0x0),
            address(phenixVestingContract),
            _totalSupply
        );
    }

    /**
     * @dev Swapping switch used to mitigate any calculation
     * issues during swapBack.
     */
    modifier noReentrancy() {
        inSwap = true;
        _;
        inSwap = false;
    }

    modifier initialDistributionLock() {
        require(
            initialDistributionFinished ||
                isOwner() ||
                _allowTransfer[msg.sender]
        );
        _;
    }

    modifier validRecipient(address to) {
        require(to != address(0x0));
        _;
    }

    /**
     * @dev Updates the autoRebaseState state. Only callable by
     * owner address. This will also reset the last rebase time.
     * @param _state boolean state for autoRebaseState.
     */
    function _updateAutoRebaseState(bool _state) internal {
        autoRebaseState = _state;
        lastRebaseTimestamp = block.timestamp;
    }

    /**
     * @dev Updates the autoRebaseState state. Only callable by
     * owner address.
     * @return next rebase delta as uint256 value.
     */
    function getNextRebase() public view returns (uint256) {
        uint256 currentTimestamp = block.timestamp;

        uint256 rebaseTimestampDelta = currentTimestamp - lastRebaseTimestamp;

        uint256 nextScaledRebaseIntervalPercentage = rebaseTimestampDelta
            .mul(REBASE_SCALING_VALUE)
            .div(REBASE_INTERVAL);

        uint256 nextRebaseDelta = _totalSupply
            .mul(rebasePercentDelta)
            .div(rebaseDenominator)
            .mul(nextScaledRebaseIntervalPercentage)
            .div(REBASE_SCALING_VALUE);

        return nextRebaseDelta;
    }

    /**
     * @dev Rebases total token supply based on the getNextRebase()
     * return result. Rebase is capped when MAX_SUPPLY is reached.
     */
    function _rebase() internal {
        uint256 supplyDelta = getNextRebase();
        _totalSupply = _totalSupply.add(uint256(supplyDelta));

        if (_totalSupply > MAX_SUPPLY) {
            _totalSupply = MAX_SUPPLY;
        }

        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);

        lastRebaseDelta = supplyDelta;
        lastRebaseTimestamp = block.timestamp;

        emit Rebase(_totalSupply);
    }

    /**
     * @dev Returns total token supply. Overrides ERC-20
     * totalSupply() function to return elastic supply.
     */
    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev Transfers amount tokens to an address.
     * @param to Receiver of the transfered tokens.
     * @param value Amount of tokens that are received.
     * @return true
     */
    function transfer(address to, uint256 value)
        external
        override
        validRecipient(to)
        initialDistributionLock
        returns (bool)
    {
        _transferFrom(msg.sender, to, value);
        return true;
    }

    /**
     * @dev Updates LP contract address and removes
     * fees from the given address.
     * @param _address Update LP contract address.
     */
    function setLP(address _address) external onlyOwner {
        pairContract = InterfaceLP(_address);
        _taxableAddress[_address] = true;
    }

    /**
     * @dev Updates given address' taxable status.
     * @param _address Subject address of taxable state adjustment.
     * @param _status State if address should be taxed.
     */
    function setTaxableAddress(address _address, bool _status)
        external
        onlyOwner
    {
        _taxableAddress[_address] = _status;
    }

    /**
     * @dev Returns spender alloance of an owner address.
     * Overides ERC-20 allowance(address, address) function
     * to return allowed fragments.
     * @param owner Owner address of tokens.
     * @param spender Spender address of tokens.
     * @return uint256 Amount of allowed tokens for the spender to use.
     */
    function allowance(address owner, address spender)
        external
        view
        override
        returns (uint256)
    {
        return _allowedFragments[owner][spender];
    }

    /**
     * @dev Returns balance of given address. Overrides
     * ERC-20 balanceOf(address) to provide balance based
     * on holder gons and gonsPerFragment.
     * @param who Balance of address.
     * @return uint256 value of address balance.
     */
    function balanceOf(address who) external view override returns (uint256) {
        return _gonBalances[who].div(_gonsPerFragment);
    }

    /**
     * @dev Performs basic token transfer. Used as
     * internal function in _transferFrom(address,
     * address, uint256) function.
     * @param from sender address of transfer.
     * @param to receiver adddress of transfer.
     * @param amount amount of tokens for receiver.
     * @return true.
     */
    function _basicTransfer(
        address from,
        address to,
        uint256 amount
    ) internal returns (bool) {
        uint256 gonAmount = amount.mul(_gonsPerFragment);
        _gonBalances[from] = _gonBalances[from].sub(gonAmount);
        _gonBalances[to] = _gonBalances[to].add(gonAmount);
        return true;
    }

    /**
     * @dev Transfers token from sender address
     * to receiver address. Performs token supply
     * rebase provided it is acceptable. Executes
     * _baseTransfer(address, address, uint256) if
     * swap is in progress.
     * @param sender sender address of transfer.
     * @param to receiver adddress of transfer.
     * @param amount amount of tokens for receiver.
     * @return true.
     */
    function _transferFrom(
        address sender,
        address to,
        uint256 amount
    ) internal returns (bool) {
        if (
            autoRebaseState == true &&
            _shouldRebase() &&
            (_taxableAddress[sender] || _taxableAddress[to])
        ) {
            _rebase();
            if (_taxableAddress[to] == true) {
                pairContract.sync();
            }
        }

        if (inSwap) {
            return _basicTransfer(sender, to, amount);
        }

        uint256 gonAmount = amount.mul(_gonsPerFragment);

        if (_shouldSwapBack()) {
            _swapBack();
        }

        _gonBalances[sender] = _gonBalances[sender].sub(gonAmount);

        uint256 gonAmountReceived = _shouldTakeFee(sender, to)
            ? _takeFee(sender, to, gonAmount)
            : gonAmount;
        _gonBalances[to] = _gonBalances[to].add(gonAmountReceived);

        emit Transfer(sender, to, gonAmountReceived.div(_gonsPerFragment));

        return true;
    }

    /**
     * @dev Transfers token from sender address
     * to receiver address. Overrides ERC-20
     * transferFrom(address, address, uint256) to
     * check value of allowed fragments that sender
     * can access from the owner (from address).
     * @param from sender address of transfer.
     * @param to receiver adddress of transfer.
     * @param value amount of tokens for receiver.
     * @return true.
     */
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external override validRecipient(to) returns (bool) {
        if (_allowedFragments[from][msg.sender] != uint256(-1)) {
            _allowedFragments[from][msg.sender] = _allowedFragments[from][
                msg.sender
            ].sub(value, "Insufficient Allowance");
        }

        _transferFrom(from, to, value);
        return true;
    }

    /**
     * @dev Executes fee allocations and distributes tokens
     * to contract address, phenix vault receiver address, and
     * liquidity receiver address. Does not liquify tokens if
     * over-liquified (determined by isOverLiquified() function).
     */
    function _swapBack() internal noReentrancy {
        uint256 dynamicLiquidityFee = isOverLiquified() ? 0 : liquidityFee;
        uint256 contractTokenBalance = _gonBalances[address(this)].div(
            _gonsPerFragment
        );
        uint256 amountToLiquify = contractTokenBalance
            .mul(dynamicLiquidityFee)
            .div(totalFee)
            .div(2);
        uint256 amountToSwap = contractTokenBalance.sub(amountToLiquify);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        uint256 balanceBefore = address(this).balance;

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 amountETH = address(this).balance.sub(balanceBefore);

        uint256 totalETHFee = totalFee.sub(dynamicLiquidityFee.div(2));

        uint256 amountETHLiquidity = amountETH
            .mul(dynamicLiquidityFee)
            .div(totalETHFee)
            .div(2);

        if (amountToLiquify > 0) {
            router.addLiquidityETH{value: amountETHLiquidity}(
                address(this),
                amountToLiquify,
                0,
                0,
                liquidityReceiver,
                block.timestamp
            );
        }

        (bool success, ) = payable(phenixFundReserveReciever).call{
            value: address(this).balance
        }("");
    }

    /**
     * @dev Calculates swap fee and returns new allocation
     * of swap based on swap conditions. Calculate is based
     * on liquidity fee and phenix vault fee. Sell fee will also
     * be taken into consideration if receiver is pair address.
     * @return uint256 gonAmount that is transfered in the swap.
     */
    function _takeFee(
        address sender,
        address to,
        uint256 gonAmount
    ) internal returns (uint256) {
        uint256 _totalFee = totalFee;
        if (_taxableAddress[to] == true) _totalFee = _totalFee.add(sellFee);

        uint256 feeAmount = gonAmount.mul(_totalFee).div(feeDenominator);

        _gonBalances[address(this)] = _gonBalances[address(this)].add(
            feeAmount
        );
        emit Transfer(sender, address(this), feeAmount.div(_gonsPerFragment));

        return gonAmount.sub(feeAmount);
    }

    /**
     * @dev Decreases spender allowance of sender address.
     * @param spender Spender address.
     * @param subtractedValue Amount to reduce spender allowance by.
     * @return bool
     */
    function decreaseAllowance(address spender, uint256 subtractedValue)
        external
        initialDistributionLock
        returns (bool)
    {
        uint256 oldValue = _allowedFragments[msg.sender][spender];
        if (subtractedValue >= oldValue) {
            _allowedFragments[msg.sender][spender] = 0;
        } else {
            _allowedFragments[msg.sender][spender] = oldValue.sub(
                subtractedValue
            );
        }
        emit Approval(
            msg.sender,
            spender,
            _allowedFragments[msg.sender][spender]
        );
        return true;
    }

    /**
     * @dev Updates router address
     * @param _address address to set for the dex router
     */
    function updateRouter(address _address) external onlyOwner {
        require(address(router) != _address, "Router address already set");
        router = IVVSRouter(_address);
    }

    /**
     * @dev Increases spender allowance of sender address.
     * @param spender Spender address.
     * @param addedValue Amount to increase spender allowance by.
     * @return bool
     */
    function increaseAllowance(address spender, uint256 addedValue)
        external
        initialDistributionLock
        returns (bool)
    {
        _allowedFragments[msg.sender][spender] = _allowedFragments[msg.sender][
            spender
        ].add(addedValue);
        emit Approval(
            msg.sender,
            spender,
            _allowedFragments[msg.sender][spender]
        );
        return true;
    }

    /**
     * @dev Approves spender address to use sender tokens.
     * @param spender Spender address.
     * @param value Amount of tokens spender can access.
     * @return bool
     */
    function approve(address spender, uint256 value)
        external
        override
        initialDistributionLock
        returns (bool)
    {
        _allowedFragments[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /**
     * @dev Checks if given address is exempt from swap fees.
     * @param _addr Address to check current exemption status.
     * @return bool
     */
    function checkFeeExempt(address _addr) external view returns (bool) {
        return _isFeeExempt[_addr];
    }

    /**
     * @dev Unlocks tokens and sets initialDistributedFinished
     * to true. Only callable from owner address.
     */
    function setInitialDistributionFinished() external onlyOwner {
        initialDistributionFinished = true;
    }

    /**
     * @dev Enables transfers for a specific address.
     * Only callable from owner address.
     * @param _addr Address to enable transfers.
     */
    function enableTransfer(address _addr) external onlyOwner {
        _allowTransfer[_addr] = true;
    }

    /**
     * @dev Sets given address to have exceptions from
     * swap fees. Only callable from owner address.
     * @param _addr Address to set fee exemptions.
     */
    function setFeeExempt(address _addr) external onlyOwner {
        _isFeeExempt[_addr] = true;
    }

    /**
     * @dev Checks if a token supply rebase is ready to
     * execute. Function utilized in _transferFrom(address,
     * address, uint256) internal function.
     * @return bool True if rebase can execute.
     */
    function _shouldRebase() internal view returns (bool) {
        return (uint256(block.timestamp).sub(lastRebaseTimestamp) >
            minimumRebaseTimestampDelta);
    }

    /**
     * @dev Checks if a sender (from) and receiver
     * (to) need swap fees applied in transfer. Used
     * in _transferFrom(address, address, uint256) internal
     * function. Should only apply when user is interacting with
     * the pair (to or from)
     * @param from Sender address of swap
     * @param to Receiver address of swap.
     * @return bool True if fees apply on transfer.
     */
    function _shouldTakeFee(address from, address to)
        internal
        view
        returns (bool)
    {
        return
            (_taxableAddress[from] || _taxableAddress[to]) &&
            (!_isFeeExempt[from] || !_isFeeExempt[to]);
    }

    /**
     * @dev Updates swap back settings.
     * @param _enabled bool value to determine of swap back is enabled.
     * @param _num uint256 value for the swap back threshhold
     * @param _denom uint256 value used for the threshold deminator
     */
    function setSwapBackSettings(
        bool _enabled,
        uint256 _num,
        uint256 _denom
    ) external onlyOwner {
        swapEnabled = _enabled;
        gonSwapThreshold = TOTAL_GONS.div(_denom).mul(_num);
    }

    /**
     * @dev Configures Rebase settings. Set AutoRebaseState,
     * RebasePercentDelta, and Accuracy.
     * @param _autoRebaseState True if rebase on each transfer
     * @param _percentage value of rebase percent delta based on a daily interval (18)
     * @param _accuracy defines the value of the rebase delta percentage demoninator (1000)
     */
    function setRebaseSettings(
        bool _autoRebaseState,
        uint256 _percentage,
        uint256 _accuracy
    ) external onlyOwner {
        _updateAutoRebaseState(_autoRebaseState);
        rebasePercentDelta = _percentage;
        rebaseDenominator = _accuracy;
    }

    /**
     * @dev Check whether the a swap back can be performed.
     * @return bool, true if swapBack is allowed to execute.
     */
    function _shouldSwapBack() internal view returns (bool) {
        return
            _taxableAddress[msg.sender] == false &&
            !inSwap &&
            swapEnabled &&
            _gonBalances[address(this)] >= gonSwapThreshold;
    }

    /**
     * @dev Returns current circulating token supply
     * @return uint256, value of total circulating supply.
     */
    function getCirculatingSupply() public view returns (uint256) {
        return
            (TOTAL_GONS.sub(_gonBalances[DEAD]).sub(_gonBalances[ZERO])).div(
                _gonsPerFragment
            );
    }

    function setTargetLiquidity(uint256 target, uint256 accuracy)
        external
        onlyOwner
    {
        targetLiquidity = target;
        targetLiquidityDenominator = accuracy;
    }

    function isNotInSwap() external view returns (bool) {
        return !inSwap;
    }

    function checkSwapThreshold() external view returns (uint256) {
        return gonSwapThreshold.div(_gonsPerFragment);
    }

    function setFeeReceivers(
        address _liquidityReceiver,
        address _phenixFundReserveReciever
    ) external onlyOwner {
        liquidityReceiver = _liquidityReceiver;
        phenixFundReserveReciever = _phenixFundReserveReciever;
    }

    function setFees(
        uint256 _liquidityFee,
        uint256 _phenixVaultFee,
        uint256 _sellFee,
        uint256 _feeDenominator
    ) external onlyOwner {
        liquidityFee = _liquidityFee;
        phenixVaultFee = _phenixVaultFee;
        sellFee = _sellFee;
        totalFee = liquidityFee.add(phenixVaultFee);
        feeDenominator = _feeDenominator;
        require(totalFee < feeDenominator / 4);
    }

    function getLiquidityBacking() public view returns (uint256) {
        uint256 liquidityBalance = _gonBalances[pair].div(_gonsPerFragment);
        return
            targetLiquidityDenominator.mul(liquidityBalance.mul(2)).div(
                getCirculatingSupply()
            );
    }

    function isOverLiquified() public view returns (bool) {
        return getLiquidityBacking() > targetLiquidity;
    }

    receive() external payable {}
}
