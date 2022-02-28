pragma solidity ^0.7.4;

// SPDX-License-Identifier: MIT

import "./Ownable.sol";
import "./SafeMath.sol";
import "./IERC20.sol";
import "./IVVSRouter.sol";

contract PhenixTokenVesting is Ownable {
    using SafeMath for uint256;

    address private tokenAddress;
    address private pairAddress;
    uint256 private unlockTimestamp;
    uint256 private burnLimitPercentage;
    uint256 private burnLimitDenominator;
    uint256 public burnTimestampDifference;
    uint256 public lastBurnTimestamp;
    uint256 private buyBackPercentageAllocation;
    uint256 private buyBackPercentageDenominator;
    uint256 public buyBackAllocation;
    uint256 public totalTokensBurned;
    mapping(address => bool) private authorizedReceiver;
    IVVSRouter public router;

    address constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    constructor(
        address _tokenAddress,
        address _pairAddress,
        address _owner
    ) {
        tokenAddress = _tokenAddress;
        pairAddress = _pairAddress;
        unlockTimestamp = block.timestamp;
        authorizedReceiver[msg.sender] = true;

        burnLimitPercentage = 1;
        burnLimitDenominator = 100;
        burnTimestampDifference = 432000;
        totalTokensBurned = 0;
        lastBurnTimestamp = block.timestamp;

        buyBackPercentageAllocation = 20;
        buyBackPercentageDenominator = 100;
        buyBackAllocation = 0;

        router = IVVSRouter(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);

        _transferOwnership(_owner);
    }

    event WithdrawTokens(address indexed _address, uint256 indexed _amount);
    event WithdrawPairTokens(address indexed _address, uint256 indexed _amount);
    event BurnTokens(uint256 indexed _amount);
    event SetAuthorizedReceiver(address indexed _address, bool indexed _status);

    /**
     * @dev Updates the authorizedReciever state of a given address. An
     * authorizedReceiver is allowed to withdraw tokens. Owner only.
     */
    function setAuthorizedReceiver(address _address, bool _status)
        public
        onlyOwner
    {
        authorizedReceiver[_address] = _status;
    }

    /**
     * @dev Increases the token timelock value by a given amount.
     */
    function increaseTimeLock(uint256 _amount) external onlyOwner {
        unlockTimestamp = unlockTimestamp + _amount;
    }

    /**
     * @dev Withdraw tokens from the vesting contract. Requires that the
     * caller is an authorizedReceiver and that the timelock has expired.
     */
    function withdrawTokens(uint256 _amount) external {
        require(
            IERC20(tokenAddress).balanceOf(address(this)) >= _amount,
            "Not enough tokens."
        );
        require(
            authorizedReceiver[msg.sender] == true,
            "Not authorized receiver."
        );
        require(block.timestamp > unlockTimestamp, "Not unlocked.");

        IERC20(tokenAddress).transfer(msg.sender, _amount);

        emit WithdrawTokens(msg.sender, _amount);
    }

    /**
     * @dev Withdraw pair tokens from the vesting contract. Requires that the
     * caller is an authorizedReceiver and that the timelock has expired.
     */
    function withdrawPairTokens(uint256 _amount) external {
        require(
            IERC20(pairAddress).balanceOf(address(this)) >= _amount,
            "Not enough tokens."
        );
        require(
            authorizedReceiver[msg.sender] == true,
            "Not authorized receiver."
        );
        require(block.timestamp > unlockTimestamp, "Not unlocked.");

        IERC20(pairAddress).transfer(msg.sender, _amount);

        emit WithdrawPairTokens(msg.sender, _amount);
    }

    function swapAndBurnTokens(uint256 _amountEth) external {
        require(
            _amountEth <= buyBackAllocation,
            "Not enough buy back allocation"
        );
        buyBackAllocation = buyBackAllocation.sub(_amountEth);

        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(tokenAddress);
        uint256 deadline = block.timestamp + 60;

        uint256[] amountsOut = swapExactETHForTokensSupportingFeeOnTransferTokens(
                0,
                path,
                address(this),
                deadline
            );

        IERC20(tokenAddress).transfer(BURN_ADDRESS, amountsOut[1]);
        totalTokensBurned = totalTokensBurned.add(amountsOut[1]);
        emit BurnTokens(amountsOut[1]);
    }

    /**
     * @dev Sets the token address. Requires that the new address
     * doesn't equal the current address and that the caller is the
     * owner.
     */
    function setTokenAddress(address _address) external onlyOwner {
        require(_address != tokenAddress, "Token address already set.");
        tokenAddress = _address;
    }

    /**
     * @dev Sets the pair token address. Requires that the new address
     * doesn't equal the current address and that the caller is the
     * owner.
     */
    function setPairTokenAddress(address _address) external onlyOwner {
        require(_address != pairAddress, "Pair token address already set.");
        pairAddress = _address;
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
     * @dev Burns a given amount of tokens within the vesting contract.
     * Requires that the caller is an authorizedReceiver.
     */
    function burnTokens(uint256 _amount) external {
        require(
            authorizedReceiver[msg.sender] == true,
            "Not authorized receiver."
        );

        require(canBurnTokens(_amount), "Cannot burn tokens.");

        IERC20(tokenAddress).transfer(BURN_ADDRESS, _amount);
        lastBurnTimestamp = block.timestamp;
        totalTokensBurned = totalTokensBurned.add(_amount);
        emit BurnTokens(_amount);
    }

    /**
     * @dev Withdraw funds from the vesting contract. Requires that the
     * caller is an authorizedReceiver.
     */
    function withdrawFunds() external {
        require(
            authorizedReceiver[msg.sender] == true,
            "Not authorized receiver."
        );

        (bool success, ) = payable(msg.sender).call{
            value: address(this).balance
        }("");

        require(success, "No funds to withdrawal.");
    }

    function getTokenBurnLimit() public view returns (uint256) {
        return
            uint256(IERC20(tokenAddress).balanceOf(address(this)))
                .mul(burnLimitPercentage)
                .div(burnLimitDenominator);
    }

    function canBurnTokens(uint256 _tokenAmount) public view returns (bool) {
        return
            _tokenAmount <= getTokenBurnLimit() &&
            block.timestamp > lastBurnTimestamp.add(burnTimestampDifference);
    }

    function setBurnTokenSettings(
        uint256 _burnLimitPercentage,
        uint256 _burnLimitDenominator
    ) external onlyOwner {
        burnLimitPercentage = _burnLimitPercentage;
        burnLimitDenominator = _burnLimitDenominator;
    }

    /**
     * @dev Returns true if the token timelock is unlocked.
     */
    function isTokensUnlocked() external view returns (bool) {
        return block.timestamp > unlockTimestamp;
    }

    /**
     * @dev Returns unix timestamp of time unlock.
     */
    function getUnlockTimestamp() external view returns (uint256) {
        return unlockTimestamp;
    }

    /**
     * @dev Returns current address of token.
     */
    function getTokenAddress() external view returns (address) {
        return tokenAddress;
    }

    /**
     * @dev Returns current address of pair token.
     */
    function getPairAddress() external view returns (address) {
        return pairAddress;
    }

    function _updateBuyBackAllocation(uint256 _amountEth) internal {
        buyBackAllocation = buyBackAllocation.add(
            _amountEth.mul(buyBackPercentageAllocation).div(
                buyBackPercentageDenominator
            )
        );
    }

    receive() external payable {
        _updateBuyBackAllocation(msg.value);
    }
}
