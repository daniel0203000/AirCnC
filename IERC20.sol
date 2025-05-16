// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IERC20 {   // 定義一個介面 ERC20 標準的規格

    event Transfer(address indexed from, address indexed to, uint256 value); // 定義轉帳事件，誰轉給誰多少
    event Approval(address indexed owner, address indexed spender, uint256 value); // 定義授權事件，誰授權誰多少額度

    function totalSupply() external view returns (uint256); // 回傳總供應量

    function balanceOf(address account) external view returns (uint256); // 查詢某個帳戶的餘額

    function transfer(address to, uint256 amount) external returns (bool); // 從自己帳戶轉錢給別人

    function allowance(address owner, address spender) external view returns (uint256); // 查某人給另一個人的授權額度

    function approve(address spender, uint256 amount) external returns (bool); // 授權某人可以幫你花多少錢

    function transferFrom(
        address from, // 被扣款的人
        address to,   // 收錢的人
        uint256 amount // 金額
    ) external returns (bool); // 用於代替別人轉帳給別人
    }
