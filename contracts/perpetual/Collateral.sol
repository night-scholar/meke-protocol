// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../lib/LibMath.sol";
import "../lib/LibTypes.sol";
import "./PerpetualGovernance.sol";

/**
 *  Contract Collateral handles operations of underlaying collateral.
 *  Supplies methods to manipulate cash balance.
 */
contract Collateral is PerpetualGovernance {
    using LibMathSigned for int256;
    using LibMathUnsigned for uint256;
    using SafeERC20 for IERC20;

    // Available decimals should be within [0, 18]
    uint256 private constant MAX_DECIMALS = 18;

    event Deposit(address indexed trader, int256 wadAmount, int256 balance);
    event Withdraw(address indexed trader, int256 wadAmount, int256 balance);

    /**
     * @dev Constructor of Collateral contract. Initialize collateral type and decimals.
     * @param _collateral   Address of collateral token. 0x0 means using ether instead of erc20 token.
     * @param _decimals     Decimals of collateral token. The value should be within range [0, 18].
     */
    constructor(address _globalConfig, address _collateral, uint256 _decimals)
        PerpetualGovernance(_globalConfig)
    {
        require(_decimals <= MAX_DECIMALS, "decimals out of range");
        require(_collateral != address(0) || _decimals == 18, "invalid decimals");

        collateral = IERC20(_collateral);
        // This statement will cause a 'InternalCompilerError: Assembly exception for bytecode'
        // scaler = (_decimals == MAX_DECIMALS ? 1 : 10**(MAX_DECIMALS.sub(_decimals))).toInt256();
        // But this will not.
        scaler = int256(10**(MAX_DECIMALS - _decimals));
    }

    // ** All interface call from upper layer use the decimals of the collateral, called 'rawAmount'.

    /**
     * @dev Indicates that whether current collateral is an erc20 token.
     * @return True if current collateral is an erc20 token.
     */
    function isTokenizedCollateral() internal view returns (bool) {
        return address(collateral) != address(0);
    }

    /**
     * @dev Deposit collateral into trader's colleteral account. Decimals of collateral will be converted into internal
     *      decimals (18) then.
     *      For example:
     *          For a USDT-ETH contract, depositing 10 ** 6 USDT will increase the cash balance by 10 ** 18.
     *          But for a DAI-ETH contract, the depositing amount should be 10 ** 18 to get the same cash balance.
     *
     * @param trader    Address of account owner.
     * @param rawAmount Amount of collateral to be deposited in its original decimals.
     */
    function deposit(address trader, uint256 rawAmount) internal {
        int256 wadAmount = pullCollateral(trader, rawAmount);
        marginAccounts[trader].cashBalance = marginAccounts[trader].cashBalance.add(wadAmount);
        if (marginAccounts[trader].side == LibTypes.Side.FLAT){
            LibTypes.MarginAccount storage account = marginAccounts[trader];
            account.side = LibTypes.Side.EMPTY;
            account.size = flatAmount;
            account.entryValue = flatAmount;
            account.entrySocialLoss = flatAmount.toInt256();
            account.entryFundingLoss = flatAmount.toInt256();
        }
        emit Deposit(trader, wadAmount, marginAccounts[trader].cashBalance);
    }

    /**
     * @dev Withdraw collaterals from trader's margin account to his ethereum address.
     *      The amount to withdraw is in its original decimals.
     *
     * @param trader    Address of account owner.
     * @param rawAmount Amount of collateral to be deposited in its original decimals.
     */
    function withdraw(address payable trader, uint256 rawAmount) internal {
        require(rawAmount > 0, "amount must be greater than 0");
        require(marginAccounts[trader].side != LibTypes.Side.FLAT,"size can not be FLAT");
        int256 wadAmount = toWad(rawAmount);
        require(wadAmount <= marginAccounts[trader].cashBalance, "insufficient balance");
        marginAccounts[trader].cashBalance = marginAccounts[trader].cashBalance.sub(wadAmount);
        pushCollateral(trader, rawAmount);

        emit Withdraw(trader, wadAmount, marginAccounts[trader].cashBalance);
    }

    /**
     * @dev Transfer collateral from user if collateral is erc20 token.
     *
     * @param trader    Address of account owner.
     * @param rawAmount Amount of collateral to be transferred into contract.
     * @return wadAmount Internal representation of the raw amount.
     */
    function pullCollateral(address trader, uint256 rawAmount) internal returns (int256 wadAmount) {
        require(rawAmount > 0, "amount must be greater than 0");
        if (isTokenizedCollateral()) {
            collateral.safeTransferFrom(trader, address(this), rawAmount);
        }
        wadAmount = toWad(rawAmount);
    }

    /**
     * @dev Transfer collateral to user no matter erc20 token or ether.
     *
     * @param trader    Address of account owner.
     * @param rawAmount Amount of collateral to be transferred to user.
     * @return wadAmount Internal representation of the raw amount.
     */
    function pushCollateral(address payable trader, uint256 rawAmount) internal returns (int256 wadAmount) {
        if (isTokenizedCollateral()) {
            collateral.safeTransfer(trader, rawAmount);
        } else {
            Address.sendValue(trader, rawAmount);
        }
        return toWad(rawAmount);
    }

    /**
     * @dev Convert the represention of amount from raw to internal.
     *
     * @param rawAmount Amount with decimals of collateral.
     * @return amount Amount with internal decimals.
     */
    function toWad(uint256 rawAmount) internal view returns (int256) {
        return rawAmount.toInt256().mul(scaler);
    }

    /**
     * @dev Convert the represention of amount from internal to raw.
     *
     * @param amount Amount with internal decimals.
     * @return amount Amount with decimals of collateral.
     */
    function toCollateral(int256 amount) internal view returns (uint256) {
        return amount.div(scaler).toUint256();
    }
}
