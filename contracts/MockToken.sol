pragma solidity ^0.4.23;


import "openzeppelin-solidity/contracts/token/ERC20/MintableToken.sol";

contract MockToken is MintableToken {

    string public name = "MOCK COIN";
    string public symbol = "MCK";
    uint8 public decimals = 18;

}