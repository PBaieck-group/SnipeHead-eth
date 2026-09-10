// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.7.0
pragma solidity ^0.8.27;

//  ███████╗███╗   ██╗██╗██████╗ ███████╗██╗  ██╗███████╗ █████╗ ██████╗ 
//  ██╔════╝████╗  ██║██║██╔══██╗██╔════╝██║  ██║██╔════╝██╔══██╗██╔══██╗
//  ███████╗██╔██╗ ██║██║██████╔╝█████╗  ███████║█████╗  ███████║██║  ██║
//  ╚════██║██║╚██╗██║██║██╔═══╝ ██╔══╝  ██╔══██║██╔══╝  ██╔══██║██║  ██║
//  ███████║██║ ╚████║██║██║     ███████╗██║  ██║███████╗██║  ██║██████╔╝
//  ╚══════╝╚═╝  ╚═══╝╚═╝╚═╝     ╚══════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═════╝

//  THE LEGEND OF SNIPEHEAD
//
//  Once upon a time, there was a boy everyone called Snipehead.
//
//  At school, the other kids teased him because his head was shaped
//  like a snipehead. They laughed, pointed, and made jokes about him.
//  But Snipehead never fought back. He turned the other cheek and
//  kept his head held high.
//
//  Then one day, an emergency struck the school.
//
//  When everyone else was scared and didn't know what to do,
//  Snipehead stepped forward. His enormous head, the very thing
//  everyone had once made fun of, became the thing that saved them.
//
//  He used his giant head to shield the kids and help everyone
//  get to safety.
//
//  From that day forward, nobody laughed at him anymore.
//
//  They called him by a new name:
//
//  SNIPEHEAD THE GREAT.
//
//  And they learned that the thing that makes you different
//  might just be the thing that makes you great.

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/// @custom:security-contact https://github.com/PBaieck-group/
contract SnipeHead is ERC20, ERC20Permit {
    constructor(address recipient)
        ERC20("SnipeHead", "SHD")
        ERC20Permit("SnipeHead")
    {
        _mint(recipient, 1000000000 * 10 ** decimals());
    }
}
