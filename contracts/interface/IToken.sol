// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IToken {
    /// @notice Initialize the token
    /// @dev This can only be called once, the caller would become the owner of the token
    ///      - The decimal is fixed to 18
    /// @param _symbol  The name of the token
    /// @param _name  The symbol of the token
    /// @param _totalSupply  The maximum supply of the token
    /// @param _owner  The owner authority of the token
    /// @param _dest  The receiver of the initial mint
    function initialize(string memory _symbol, string memory _name, uint256 _totalSupply, address _owner, address _dest) external;
}