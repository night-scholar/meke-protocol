// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.7.6;
pragma abicoder v2;

import "../lib/LibSignature.sol";


contract TestSignature {
    function isValidSignature(LibSignature.OrderSignature memory signature, bytes32 hash, address signerAddress)
        public
        pure
        returns (bool)
    {
        return LibSignature.isValidSignature(signature, hash, signerAddress);
    }
}
