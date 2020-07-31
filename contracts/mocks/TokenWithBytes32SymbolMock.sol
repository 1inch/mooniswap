// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;


contract TokenWithBytes32SymbolMock {
    bytes32 public symbol = "ABC";

    constructor(bytes32 s) public {
        symbol = s;
    }
}
