// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../lib/LibMath.sol";
import "../lib/LibTypes.sol";

import "../interface/IFunding.sol";
import "../interface/IGlobalConfig.sol";


contract PerpetualStorage {
    using LibMathSigned for int256;
    using LibMathUnsigned for uint256;

    bool public paused = false;
    bool public withdrawDisabled = false;

    uint256 public flatAmount = 10**18;

    // Global configuation instance address
    IGlobalConfig public globalConfig;
    // funding module address
    IFunding public fundingModule;
    // Address of collateral;
    IERC20 public collateral;
    // DEV address
    address public devAddress;
    // Status of perpetual
    LibTypes.Status public status;
    // Settment price replacing index price in settled status
    uint256 public settlementPrice;
    // Governance parameters
    LibTypes.PerpGovernanceConfig internal governance;
    // Insurance balance
    int256 public insuranceFundBalance;
    // Total size
    uint256[3] internal totalSizes;
    // Socialloss
    int256[3] internal socialLossPerContracts;
    // Scaler helps to convert decimals
    int256 internal scaler;
    // Mapping from owner to its margin account
    mapping (address => LibTypes.MarginAccount) internal marginAccounts;

    // TODO: Should be UpdateSocialLoss but to compatible off-chain part
    event SocialLoss(LibTypes.Side side, int256 newVal);

    /**
     * @dev Helper to access social loss per contract.
     *      FLAT is always 0.
     *
     * @param side Side of position.
     * @return Total opened position size of given side.
     */
    function socialLossPerContract(LibTypes.Side side) public view returns (int256) {
        return socialLossPerContracts[uint256(side)];
    }

    /**
     * @dev Help to get total opend position size of every side.
     *      FLAT is always 0 and LONG should always equal to SHORT.
     *
     * @param side Side of position.
     * @return Total opened position size of given side.
     */
    function totalSize(LibTypes.Side side) public view returns (uint256) {
        return totalSizes[uint256(side)];
    }

    /**
     * @dev Return data structure of current governance parameters.
     *
     * @return Data structure of current governance parameters.
     */
    function getGovernance() public view returns (LibTypes.PerpGovernanceConfig memory) {
        return governance;
    }

    /**
     * @dev Get underlaying data structure of a margin account.
     *
     * @param trader   Address of the account owner.
     * @return Margin account data.
     */
    function getMarginAccount(address trader) public view returns (LibTypes.MarginAccount memory) {
        // return marginAccounts[trader];

        LibTypes.MarginAccount memory account= marginAccounts[trader];
        if (account.side == LibTypes.Side.FLAT && account.size == flatAmount){
            account.size = account.size.sub(flatAmount);
            account.entryValue = account.entryValue.sub(flatAmount);
            account.entryFundingLoss = account.entryFundingLoss.sub(flatAmount.toInt256());
            account.entrySocialLoss = account.entrySocialLoss.sub(flatAmount.toInt256());
            return account;
        }
        return account;
    }
}
