// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;


contract TokenWithStringSymbolMock {
    string public symbol = "ABC";

    constructor(string memory s) public {
        symbol = s;
    }
}
