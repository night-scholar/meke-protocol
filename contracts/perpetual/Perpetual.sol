// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../lib/LibOrder.sol";
import "../lib/LibTypes.sol";
import "../lib/LibMath.sol";

import "./MarginAccount.sol";

contract Perpetual is MarginAccount, ReentrancyGuard {
    using LibMathSigned for int256;
    using LibMathUnsigned for uint256;
    using LibOrder for LibTypes.Side;

    uint256 public totalAccounts;
    address[] public accountList;
    mapping(address => bool) private accountCreated;

    event CreatePerpetual();
    event Paused(address indexed caller);
    event Unpaused(address indexed caller);
    event DisableWithdraw(address indexed caller);
    event EnableWithdraw(address indexed caller);
    event CreateAccount(uint256 indexed id, address indexed trader);
    event Trade(address indexed trader, LibTypes.Side side, uint256 price, uint256 amount);
    event Liquidate(address indexed keeper, address indexed trader, uint256 price, uint256 amount);
    event EnterEmergencyStatus(uint256 price);
    event EnterSettledStatus(uint256 price);

    constructor(
        address _globalConfig,
        address _devAddress,
        address _collateral,
        uint256 _collateralDecimals
    )
        MarginAccount(_globalConfig, _collateral, _collateralDecimals)
    {
        devAddress = _devAddress;
        emit CreatePerpetual();
    }

    // disable fallback
    fallback() external payable {
        revert("fallback function disabled");
    }

    /**
     * @dev Called by a pauseControllers, put whole system into paused state.
     */
    function pause() external {
        require(
            globalConfig.pauseControllers(msg.sender) || globalConfig.owner() == msg.sender,
            "unauthorized caller"
        );
        require(!paused, "already paused");
        paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @dev Called by a pauseControllers, put whole system back to normal.
     */
    function unpause() external {
        require(
            globalConfig.pauseControllers(msg.sender) || globalConfig.owner() == msg.sender,
            "unauthorized caller"
        );
        require(paused, "not paused");
        paused = false;
        emit Unpaused(msg.sender);
    }

    /**
     * @dev Called by a withdrawControllers disable withdraw function.
     */
    function disableWithdraw() external {
        require(
            globalConfig.withdrawControllers(msg.sender) || globalConfig.owner() == msg.sender,
            "unauthorized caller"
        );
        require(!withdrawDisabled, "already disabled");
        withdrawDisabled = true;
        emit DisableWithdraw(msg.sender);
    }

    /**
     * @dev Called by a withdrawControllers, enable withdraw function again.
     */
    function enableWithdraw() external {
        require(
            globalConfig.withdrawControllers(msg.sender) || globalConfig.owner() == msg.sender,
            "unauthorized caller"
        );
        require(withdrawDisabled, "not disabled");
        withdrawDisabled = false;
        emit EnableWithdraw(msg.sender);
    }

    /**
     * @notice Force to set cash balance of margin account. Called by administrator to
     *      fix unexpected cash balance.
     *
     * @param trader Address of account owner.
     * @param amount Absolute cash balance value to be set.
     */
    function increaseCashBalance(address trader, uint256 amount) external onlyOwner {
        require(status == LibTypes.Status.EMERGENCY, "wrong perpetual status");
        updateCashBalance(trader, amount.toInt256());
    }

    /**
     * @notice Force to set cash balance of margin account. Called by administrator to
     *      fix unexpected cash balance.
     *
     * @param trader Address of account owner.
     * @param amount Absolute cash balance value to be set.
     */
    function decreaseCashBalance(address trader, uint256 amount) external onlyOwner {
        require(status == LibTypes.Status.EMERGENCY, "wrong perpetual status");
        updateCashBalance(trader, amount.toInt256().neg());
    }

    /**
     * @notice Set perpetual status to 'emergency'. It can be called multiple times to set price.
     *      In emergency mode, main function like trading / withdrawing is disabled to prevent unexpected loss.
     *
     * @param price Price used as mark price in emergency mode.
     */
    function beginGlobalSettlement(uint256 price) external onlyOwner {
        require(status != LibTypes.Status.SETTLED, "wrong perpetual status");
        status = LibTypes.Status.EMERGENCY;

        settlementPrice = price;
        emit EnterEmergencyStatus(price);
    }

    /**
     * @notice Set perpetual status to 'settled'. It can be call only once in 'emergency' mode.
     *         In settled mode, user is expected to closed positions and withdraw all the collateral.
     */
    function endGlobalSettlement() external onlyOwner {
        require(status == LibTypes.Status.EMERGENCY, "wrong perpetual status");
        status = LibTypes.Status.SETTLED;

        emit EnterSettledStatus(settlementPrice);
    }

    /**
     * @notice Deposit collateral to insurance fund to recover social loss. Note that depositing to
     *         insurance fund *DOES NOT* profit to depositor and only administrator can withdraw from the fund.
     *
     * @param rawAmount Amount to deposit.
     */
    function depositToInsuranceFund(uint256 rawAmount) external payable nonReentrant {
        checkDepositingParameter(rawAmount);

        require(rawAmount > 0, "amount must be greater than 0");
        int256 wadAmount = pullCollateral(msg.sender, rawAmount);
        insuranceFundBalance = insuranceFundBalance.add(wadAmount);
        require(insuranceFundBalance >= 0, "negtive insurance fund");

        emit UpdateInsuranceFund(insuranceFundBalance);
    }

    /**
     * @notice Withdraw collateral from insurance fund. Only administrator can withdraw from it.
     *
     * @param rawAmount Amount to withdraw.
     */
    function withdrawFromInsuranceFund(uint256 rawAmount) external onlyOwner nonReentrant {
        require(rawAmount > 0, "amount must be greater than 0");
        require(insuranceFundBalance > 0, "insufficient funds");

        int256 wadAmount = toWad(rawAmount);
        require(wadAmount <= insuranceFundBalance, "insufficient funds");
        insuranceFundBalance = insuranceFundBalance.sub(wadAmount);
        pushCollateral(msg.sender, rawAmount);
        require(insuranceFundBalance >= 0, "negtive insurance fund");

        emit UpdateInsuranceFund(insuranceFundBalance);
    }

    // End Admin functions

    // Deposit && Withdraw
    /**
     * @notice Deposit collateral to sender's margin account.
     *         When depositing ether rawAmount must strictly equal to
     *
     * @dev    Need approval
     *
     * @param rawAmount Amount to deposit.
     */
    function deposit(uint256 rawAmount) external payable {
        depositImplementation(msg.sender, rawAmount);
    }

    /**
     * @notice Withdraw collateral from sender's margin account. only available in normal state.
     *
     * @param rawAmount Amount to withdraw.
     */
    function withdraw(uint256 rawAmount) external {
        withdrawImplementation(msg.sender, rawAmount);
    }

    /**
     * @notice Close all position and withdraw all collateral remaining in sender's margin account.
     *         Settle is only available in settled state and can be called multiple times.
     */
    function settle() external nonReentrant
    {
        address payable trader = msg.sender;
        settleImplementation(trader);
        int256 wadAmount = marginAccounts[trader].cashBalance;
        if (wadAmount <= 0) {
            return;
        }
        uint256 rawAmount = toCollateral(wadAmount);
        Collateral.withdraw(trader, rawAmount);
    }

    // Deposit && Withdraw - Whitelisted Only
    /**
     * @notice Deposit collateral for trader into the trader's margin account. The collateral will be transfer
     *         from the trader's ethereum address.
     *         depositFor is only available to administrator.
     *
     * @dev    Need approval
     *
     * @param trader    Address of margin account to deposit into.
     * @param rawAmount Amount of collateral to deposit.
     */
    function depositFor(address trader, uint256 rawAmount)
        external
        payable
        onlyAuthorized
    {
        depositImplementation(trader, rawAmount);
    }

    /**
     * @notice Withdraw collateral for trader from the trader's margin account. The collateral will be transfer
     *         to the trader's ethereum address.
     *         withdrawFor is only available to administrator.
     *
     * @param trader    Address of margin account to deposit into.
     * @param rawAmount Amount of collateral to deposit.
     */
    function withdrawFor(address payable trader, uint256 rawAmount)
        external
        onlyAuthorized
    {
        withdrawImplementation(trader, rawAmount);
    }

    // Method for public properties
    /**
     * @notice Price to calculate all price-depended properties of margin account.
     *
     * @dev decimals == 18
     *
     * @return Mark price.
     */
    function markPrice() public returns (uint256) {
        return status == LibTypes.Status.NORMAL ? fundingModule.currentMarkPrice() : settlementPrice;
    }

    /**
     * @notice (initial) Margin value of margin account according to mark price.
     *                   See marginWithPrice in MarginAccount.sol.
     *
     * @param trader Address of account owner.
     * @return Initial margin of margin account.
     */
    function positionMargin(address trader) public returns (uint256) {
        return MarginAccount.marginWithPrice(trader, markPrice());
    }

    /**
     * @notice (maintenance) Margin value of margin account according to mark price.
     *         See maintenanceMarginWithPrice in MarginAccount.sol.
     *
     * @param trader Address of account owner.
     * @return Maintanence margin of margin account.
     */
    function maintenanceMargin(address trader) public returns (uint256) {
        return MarginAccount.maintenanceMarginWithPrice(trader, markPrice());
    }

    /**
     * @notice Margin balance of margin account according to mark price.
     *         See marginBalanceWithPrice in MarginAccount.sol.
     *
     * @param trader Address of account owner.
     * @return Margin balance of margin account.
     */
    function marginBalance(address trader) public returns (int256) {
        return MarginAccount.marginBalanceWithPrice(trader, markPrice());
    }

    /**
     * @notice Profit and loss of margin account according to mark price.
     *         See pnlWithPrice in MarginAccount.sol.
     *
     * @param trader Address of account owner.
     * @return Margin balance of margin account.
     */
    function pnl(address trader) public returns (int256) {
        return MarginAccount.pnlWithPrice(trader, markPrice());
    }

    /**
     * @notice Available margin of margin account according to mark price.
     *         See marginBalanceWithPrice in MarginAccount.sol.
     *
     * @param trader Address of account owner.
     * @return Margin balance of margin account.
     */
    function availableMargin(address trader) public returns (int256) {
        return MarginAccount.availableMarginWithPrice(trader, markPrice());
    }

    /**
     * @notice Test if a margin account is safe, using maintenance margin rate.
     *         A unsafe margin account will loss position through liqudating initiated by any other trader,
               to make the whole system safe.
     *
     * @param trader Address of account owner.
     * @return True if give trader is safe.
     */
    function isSafe(address trader) public returns (bool) {
        uint256 currentMarkPrice = markPrice();
        return isSafeWithPrice(trader, currentMarkPrice);
    }

    /**
     * @notice Test if a margin account is safe, using maintenance margin rate according to given price.
     *
     * @param trader           Address of account owner.
     * @param currentMarkPrice Mark price.
     * @return True if give trader is safe.
     */
    function isSafeWithPrice(address trader, uint256 currentMarkPrice) public returns (bool) {
        return
            MarginAccount.marginBalanceWithPrice(trader, currentMarkPrice) >=
            MarginAccount.maintenanceMarginWithPrice(trader, currentMarkPrice).toInt256();
    }

    /**
     * @notice Test if a margin account is bankrupt. Bankrupt is a status indicates the margin account
     *         is completely out of collateral.
     *
     * @param trader           Address of account owner.
     * @return True if give trader is safe.
     */
    function isBankrupt(address trader) public returns (bool) {
        return marginBalanceWithPrice(trader, markPrice()) < 0;
    }

    /**
     * @notice Test if a margin account is safe, using initial margin rate instead of maintenance margin rate.
     *
     * @param trader Address of account owner.
     * @return True if give trader is safe with initial margin rate.
     */
    function isIMSafe(address trader) public returns (bool) {
        uint256 currentMarkPrice = markPrice();
        return isIMSafeWithPrice(trader, currentMarkPrice);
    }

    /**
     * @notice Test if a margin account is safe according to given mark price.
     *
     * @param trader Address of account owner.
     * @param currentMarkPrice Mark price.
     * @return True if give trader is safe with initial margin rate.
     */
    function isIMSafeWithPrice(address trader, uint256 currentMarkPrice) public returns (bool) {
        return availableMarginWithPrice(trader, currentMarkPrice) >= 0;
    }

    /**
     * @notice Test if a margin account is safe according to given mark price.
     *
     * @param trader    Address of account owner.
     * @param maxAmount amount.
     * @return True if give trader is safe with initial margin rate.
     */
    function liquidate(
        address trader,
        uint256 maxAmount
    )
        public
        onlyNotPaused
        returns (uint256, uint256)
    {
        require(msg.sender != trader, "self liquidate");
        require(isValidLotSize(maxAmount), "amount must be divisible by lotSize");
        require(status != LibTypes.Status.SETTLED, "wrong perpetual status");
        require(!isSafe(trader), "safe account");

        uint256 liquidationPrice = markPrice();
        require(liquidationPrice > 0, "price must be greater than 0");

        uint256 liquidationAmount = calculateLiquidateAmount(trader, liquidationPrice);
        uint256 totalPositionSize = marginAccounts[trader].size;
        uint256 liquidatableAmount = totalPositionSize.sub(totalPositionSize.mod(governance.lotSize));
        liquidationAmount = liquidationAmount.ceil(governance.lotSize).min(maxAmount).min(liquidatableAmount);
        require(liquidationAmount > 0, "nothing to liquidate");

        uint256 opened = MarginAccount.liquidate(msg.sender, trader, liquidationPrice, liquidationAmount);
        if (opened > 0) {
            require(availableMarginWithPrice(msg.sender, liquidationPrice) >= 0, "liquidator margin");
        } else {
            require(isSafe(msg.sender), "liquidator unsafe");
        }
        emit Liquidate(msg.sender, trader, liquidationPrice, liquidationAmount);
        return (liquidationPrice, liquidationAmount);
    }

    function tradePosition(
        address taker,
        address maker,
        LibTypes.Side side,
        uint256 price,
        uint256 amount
    )
        public
        onlyNotPaused
        onlyAuthorized
        returns (uint256 takerOpened, uint256 makerOpened)
    {
        require(status != LibTypes.Status.EMERGENCY, "wrong perpetual status");
        require(side == LibTypes.Side.LONG || side == LibTypes.Side.SHORT, "side must be long or short");
        require(isValidLotSize(amount), "amount must be divisible by lotSize");

        takerOpened = MarginAccount.trade(taker, side, price, amount);
        makerOpened = MarginAccount.trade(maker, LibTypes.counterSide(side), price, amount);
        require(totalSize(LibTypes.Side.LONG) == totalSize(LibTypes.Side.SHORT), "imbalanced total size");

        emit Trade(taker, side, price, amount);
        emit Trade(maker, LibTypes.counterSide(side), price, amount);
    }

    function transferCashBalance(
        address from,
        address to,
        uint256 amount
    )
        public
        onlyNotPaused
        onlyAuthorized
    {
        require(status != LibTypes.Status.EMERGENCY, "wrong perpetual status");
        MarginAccount.transferBalance(from, to, amount.toInt256());
    }

    function registerNewTrader(address trader) internal {
        emit CreateAccount(totalAccounts, trader);
        accountList.push(trader);
        totalAccounts++;
        accountCreated[trader] = true;
    }

    /**
     * @notice Check type of collateral. If ether, rawAmount must strictly match msg.value.
     *
     * @param rawAmount Amount to deposit
     */
    function checkDepositingParameter(uint256 rawAmount) internal view {
        bool isToken = isTokenizedCollateral();
        require((isToken && msg.value == 0) || (!isToken && msg.value == rawAmount), "incorrect sent value");
    }

    /**
     * @notice Implementation as underlaying of deposit and depositFor.
     *
     * @param trader    Address the collateral will be transferred from.
     * @param rawAmount Amount to deposit.
     */
    function depositImplementation(address trader, uint256 rawAmount) internal onlyNotPaused nonReentrant {
        checkDepositingParameter(rawAmount);
        require(rawAmount > 0, "amount must be greater than 0");
        require(trader != address(0), "cannot deposit to 0 address");

        Collateral.deposit(trader, rawAmount);
        // append to the account list. make the account trackable
        if (!accountCreated[trader]) {
            registerNewTrader(trader);
        }
    }

    /**
     * @notice Implementation as underlaying of withdraw and withdrawFor.
     *
     * @param trader    Address the collateral will be transferred to.
     * @param rawAmount Amount to withdraw.
     */
    function withdrawImplementation(address payable trader, uint256 rawAmount) internal onlyNotPaused nonReentrant {
        require(!withdrawDisabled, "withdraw disabled");
        require(status == LibTypes.Status.NORMAL, "wrong perpetual status");
        require(rawAmount > 0, "amount must be greater than 0");
        require(trader != address(0), "cannot withdraw to 0 address");

        uint256 currentMarkPrice = markPrice();
        require(isSafeWithPrice(trader, currentMarkPrice), "unsafe before withdraw");

        remargin(trader, currentMarkPrice);
        Collateral.withdraw(trader, rawAmount);

        require(isSafeWithPrice(trader, currentMarkPrice), "unsafe after withdraw");
        require(availableMarginWithPrice(trader, currentMarkPrice) >= 0, "withdraw margin");
    }

    /**
     * @notice Implementation as underlaying of settle.
     *
     * @param trader    Address the collateral will be transferred to.
     */
    function settleImplementation(address trader) internal onlyNotPaused {
        require(status == LibTypes.Status.SETTLED, "wrong perpetual status");
        uint256 currentMarkPrice = markPrice();
        LibTypes.MarginAccount memory account = marginAccounts[trader];
        // if (account.size == 0) {
        //     return;
        // }
        if (account.side == LibTypes.Side.FLAT){
            return;
        }
        LibTypes.Side originalSide = account.side;
        close(account, currentMarkPrice, account.size);
        marginAccounts[trader] = account;
        emit UpdatePositionAccount(trader, account, totalSize(originalSide), currentMarkPrice);
    }

    function setFairPrice(uint256 price) public onlyAuthorized  {
        fundingModule.setFairPrice(price);
    }
}
