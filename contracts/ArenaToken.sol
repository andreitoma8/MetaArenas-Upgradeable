// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title The ARENA Token Contract
/// @author Andrei Toma
/// @notice Simple ERC20 Token Contract with minting and burning functionality
contract ArenaToken is ERC20, ERC20Burnable, Ownable {
    constructor() ERC20("Arena Token", "ARENA") {
        _mint(msg.sender, 1000000000 * 10**decimals());
    }

    /// @notice the function used by the owner to mint new tokens
    /// @param to the address to mint tokens to
    /// @param amount the amount of tokens to mint
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
