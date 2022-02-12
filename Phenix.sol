pragma solidity ^0.7.4;

// SPDX-License-Identifier: MIT

import "./ERC20Detailed.sol";
import "./IVVSFactory.sol";
import "./IVVSRouter.sol";
import "./ERC20Detailed.sol";
import "./ERC20Detailed.sol";
import "./Ownable.sol";
import "./MinterRole.sol";
import "./SafeMath.sol";
import "./SafeMathInt.sol";
import "./InterfaceLP.sol";

contract Phenix is ERC20Detailed, Ownable, MinterRole {
    using SafeMath for uint256;
    using SafeMathInt for int256;

    event Rebase(uint256 indexed epoch, uint256 totalSupply);

    InterfaceLP public pairContract;

    bool public initialDistributionFinished;

    mapping(address => bool) allowTransfer;
    mapping(address => bool) _isFeeExempt;

    modifier initialDistributionLock() {
        require(
            initialDistributionFinished ||
                isOwner() ||
                allowTransfer[msg.sender]
        );
        _;
    }

    modifier validRecipient(address to) {
        require(to != address(0x0));
        _;
    }

    uint256 private constant DECIMALS = 18;
    uint256 private constant MAX_UINT256 = ~uint256(0);

    uint256 private constant INITIAL_FRAGMENTS_SUPPLY =
        1 * 10**9 * 10**DECIMALS;

    uint256 public liquidityFee = 5;
    uint256 public phenixVaultFee = 3;
    uint256 public sellFee = 5;
    uint256 public totalFee = liquidityFee.add(phenixVaultFee);
    uint256 public feeDenominator = 100;

    uint256 public lastRebaseTimestamp = block.timestamp;
    uint256 public lastRebaseDelta = 0;
    uint256 public rebaseInterval = 86400;
    uint256 public rebasePercentDelta = 1; // 1.000 percent
    uint256 public rebaseScalingValue = 100000;
    uint256 public rebaseDenominator = 100;
    bool public autoRebaseState = false;

    address DEAD = 0x000000000000000000000000000000000000dEaD;
    address ZERO = 0x0000000000000000000000000000000000000000;

    address public liquidityReceiver;
    address public phenixVaultReceiver;

    uint256 targetLiquidity = 50;
    uint256 targetLiquidityDenominator = 100;

    IVVSRouter public router;
    address public pair;

    bool public swapEnabled = true;
    uint256 private gonSwapThreshold = (TOTAL_GONS * 10) / 10000;
    bool inSwap;
    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }

    uint256 private constant TOTAL_GONS =
        MAX_UINT256 - (MAX_UINT256 % INITIAL_FRAGMENTS_SUPPLY);

    uint256 private constant MAX_SUPPLY = ~uint128(0);

    uint256 private _totalSupply;
    uint256 private _gonsPerFragment;
    mapping(address => uint256) private _gonBalances;

    mapping(address => mapping(address => uint256)) private _allowedFragments;
    mapping(address => bool) public blacklist;

    constructor() ERC20Detailed("Phenix", "PHNX", uint8(DECIMALS)) {
        router = IVVSRouter(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3); //Sushi 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506 // Cake 0x10ED43C718714eb63d5aA57B78B54704E256024E

        pair = IVVSFactory(router.factory()).createPair(
            router.WETH(),
            address(this)
        );

        liquidityReceiver = 0xfa1D544D46c7c50d7B7d7D2e85915F1b129a9386;
        phenixVaultReceiver = address(msg.sender);

        _allowedFragments[address(this)][address(router)] = uint256(-1);
        pairContract = InterfaceLP(pair);

        _totalSupply = INITIAL_FRAGMENTS_SUPPLY;
        _gonBalances[phenixVaultReceiver] = TOTAL_GONS;
        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);

        initialDistributionFinished = false;
        _isFeeExempt[phenixVaultReceiver] = true;
        _isFeeExempt[address(this)] = true;

        _transferOwnership(phenixVaultReceiver);
        emit Transfer(address(0x0), phenixVaultReceiver, _totalSupply);
    }

    function updateBlacklist(address _user, bool _flag) public onlyOwner {
        blacklist[_user] = _flag;
    }

    function updateAutoRebaseState(bool _state) public onlyOwner {
        autoRebaseState = _state;
    }

    function getNextRebase() public view returns (uint256) {
        // calculate percentage based on last rebase
        uint256 currentTimestamp = block.timestamp;
        // seconds past since last rebase
        uint256 rebaseTimestampDelta = currentTimestamp - lastRebaseTimestamp;
        // calculate scaled percentage from rebase interval
        uint256 nextScaledRebaseIntervalPercentage = rebaseTimestampDelta
            .mul(rebaseScalingValue)
            .div(rebaseInterval);
        // calculate rebase amount based on scaled rebase interval
        uint256 nextRebaseDelta = _totalSupply
            .mul(rebasePercentDelta)
            .div(rebaseDenominator)
            .mul(nextScaledRebaseIntervalPercentage)
            .div(rebaseScalingValue);

        return nextRebaseDelta;
    }

    function rebase() external onlyOwner {
        _rebase();
    }

    function _rebase() internal {
        uint256 supplyDelta = getNextRebase();

        require(!inSwap, "Try again");
        if (supplyDelta == 0) {
            emit Rebase(block.timestamp, _totalSupply);
        }

        if (supplyDelta < 0) {
            _totalSupply = _totalSupply.sub(uint256(-supplyDelta));
        } else {
            _totalSupply = _totalSupply.add(uint256(supplyDelta));
        }

        if (_totalSupply > MAX_SUPPLY) {
            _totalSupply = MAX_SUPPLY;
        }

        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);
        pairContract.sync();

        lastRebaseDelta = supplyDelta;
        lastRebaseTimestamp = block.timestamp;

        emit Rebase(lastRebaseTimestamp, _totalSupply);
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

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

    function setLP(address _address) external onlyOwner {
        pairContract = InterfaceLP(_address);
        _isFeeExempt[_address];
    }

    function allowance(address owner_, address spender)
        external
        view
        override
        returns (uint256)
    {
        return _allowedFragments[owner_][spender];
    }

    function balanceOf(address who) external view override returns (uint256) {
        return _gonBalances[who].div(_gonsPerFragment);
    }

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

    function _transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        require(!blacklist[sender] && !blacklist[recipient], "in_blacklist");

        if (autoRebaseState == true) {
            _rebase();
        }

        if (inSwap) {
            return _basicTransfer(sender, recipient, amount);
        }

        uint256 gonAmount = amount.mul(_gonsPerFragment);

        if (shouldSwapBack()) {
            swapBack();
        }

        _gonBalances[sender] = _gonBalances[sender].sub(gonAmount);

        uint256 gonAmountReceived = shouldTakeFee(sender, recipient)
            ? takeFee(sender, recipient, gonAmount)
            : gonAmount;
        _gonBalances[recipient] = _gonBalances[recipient].add(
            gonAmountReceived
        );

        emit Transfer(
            sender,
            recipient,
            gonAmountReceived.div(_gonsPerFragment)
        );

        return true;
    }

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

    function swapBack() internal swapping {
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

        uint256 amountETHPhenixVault = amountETH.mul(phenixVaultFee).div(
            totalETHFee
        );

        (bool success, ) = payable(phenixVaultReceiver).call{
            value: amountETHPhenixVault,
            gas: 30000
        }("");

        success = false;

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
    }

    function takeFee(
        address sender,
        address recipient,
        uint256 gonAmount
    ) internal returns (uint256) {
        uint256 _totalFee = totalFee;
        if (recipient == pair) _totalFee = _totalFee.add(sellFee);

        uint256 feeAmount = gonAmount.mul(_totalFee).div(feeDenominator);

        _gonBalances[address(this)] = _gonBalances[address(this)].add(
            feeAmount
        );
        emit Transfer(sender, address(this), feeAmount.div(_gonsPerFragment));

        return gonAmount.sub(feeAmount);
    }

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

    function checkFeeExempt(address _addr) external view returns (bool) {
        return _isFeeExempt[_addr];
    }

    function setInitialDistributionFinished() external onlyOwner {
        initialDistributionFinished = true;
    }

    function enableTransfer(address _addr) external onlyOwner {
        allowTransfer[_addr] = true;
    }

    function setFeeExempt(address _addr) external onlyOwner {
        _isFeeExempt[_addr] = true;
    }

    function shouldTakeFee(address from, address to)
        internal
        view
        returns (bool)
    {
        return (pair == from || pair == to) && (!_isFeeExempt[from]);
    }

    function mint(address recipient, uint256 amount) external onlyMinter {
        _totalSupply = _totalSupply.add(uint256(amount));

        if (_totalSupply > MAX_SUPPLY) {
            _totalSupply = MAX_SUPPLY;
        }

        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);
        pairContract.sync();

        _gonBalances[recipient] = _gonBalances[recipient].add(amount);
    }

    function setSwapBackSettings(
        bool _enabled,
        uint256 _num,
        uint256 _denom
    ) external onlyOwner {
        swapEnabled = _enabled;
        gonSwapThreshold = TOTAL_GONS.div(_denom).mul(_num);
    }

    function shouldSwapBack() internal view returns (bool) {
        return
            msg.sender != pair &&
            !inSwap &&
            swapEnabled &&
            _gonBalances[address(this)] >= gonSwapThreshold;
    }

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

    function addMinter(address account) public onlyOwner {
        _addMinter(account);
    }

    function removeMinter(address account) public onlyOwner {
        _removeMinter(account);
    }

    function isNotInSwap() external view returns (bool) {
        return !inSwap;
    }

    function sendPresale(
        address[] calldata recipients,
        uint256[] calldata values
    ) external onlyOwner {
        for (uint256 i = 0; i < recipients.length; i++) {
            _transferFrom(msg.sender, recipients[i], values[i]);
        }
    }

    function checkSwapThreshold() external view returns (uint256) {
        return gonSwapThreshold.div(_gonsPerFragment);
    }

    function manualSync() external {
        InterfaceLP(pair).sync();
    }

    function setFeeReceivers(
        address _liquidityReceiver,
        address _phenixVaultReceiver
    ) external onlyOwner {
        liquidityReceiver = _liquidityReceiver;
        phenixVaultReceiver = _phenixVaultReceiver;
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

    function clearStuckBalance(uint256 amountPercentage, address adr)
        external
        onlyOwner
    {
        uint256 amountETH = address(this).balance;
        payable(adr).transfer((amountETH * amountPercentage) / 100);
    }

    function rescueToken(address tokenAddress, uint256 tokens)
        public
        onlyOwner
        returns (bool success)
    {
        return ERC20Detailed(tokenAddress).transfer(msg.sender, tokens);
    }

    function transferToAddressETH(address payable recipient, uint256 amount)
        private
    {
        recipient.transfer(amount);
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
