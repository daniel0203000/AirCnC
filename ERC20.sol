// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28; // 使用 Solidity 版本 0.8.28

import "./IERC20.sol"; // 導入 ERC20 標準的介面

contract ERC20 is IERC20 { // 宣告 ERC20 合約，並繼承 IERC20 標準介面（is 表示繼承）

    // 用來紀錄每個地址的帳戶餘額（錢包地址 => 金額）
    mapping(address => uint256) public balanceOf;

    // 雙層 mapping，紀錄哪個地址授權給誰多少代幣可以使用
    mapping(address => mapping(address => uint256)) public allowance;

    // 整體發行的代幣總量
    uint256 public totalSupply;

    // 代幣名稱
    string public name;

    // 代幣代號
    string public symbol;

    // 小數位數，這邊設成 0
    uint8 public decimals = 0;

    address public owner;

    // 建構子：部署時傳入代幣名稱與代號
    constructor(string memory name_, string memory symbol_) {
        name = name_;       // 設定代幣名稱
        symbol = symbol_;   // 設定代幣代號
        owner = msg.sender;
    }

    //轉帳
    function transfer(address recipient, uint amount) public returns (bool) {
        require(msg.sender.balance>=amount, "balance is not enough");
        require(recipient != address(0), "address is zero");
        balanceOf[msg.sender] -= amount;        // 自己扣錢
        balanceOf[recipient] += amount;         // 對方加錢
        emit Transfer(msg.sender, recipient, amount); // 發出轉帳事件
        return true; // 傳回成功
    }

    //授權功能
    function approve(address spender, uint amount) public returns (bool) {
        require(msg.sender.balance>=amount, "balance is not enough");
        require(spender != address(0), "address is zero");
        allowance[msg.sender][spender] = amount; // 授權 spender 可以幫我花多少
        emit Approval(msg.sender, spender, amount); // 發出授權事件
        return true;
    }

    //授權轉帳
    function transferFrom(address sender, address recipient, uint amount) public returns (bool) {
        require(sender.balance>=amount, "balance is not enough");
        require(recipient != address(0), "address is zero");
        require(allowance[sender][msg.sender] >=amount, "allowance is not enough");
        allowance[sender][msg.sender] -= amount; // 先扣掉授權額度
        balanceOf[sender] -= amount;             // 也扣掉 sender 本人的餘額
        balanceOf[recipient] += amount;          // 收款人加錢
        emit Transfer(sender, recipient, amount); // 發出轉帳事件
        return true;
    }

    //鍛造代幣
    function mint(uint amount) external {
        require(msg.sender == owner, "Only owner can call this");
        balanceOf[msg.sender] += amount;     // 自己加錢
        totalSupply += amount;              // 總發行量增加
        emit Transfer(address(0), msg.sender, amount); // 從 0 地址轉過來（代表發新幣）
    }

    //銷毀代幣（burn）
    function burn(uint amount) external {
        require(msg.sender == owner, "Only owner can call this");
        balanceOf[msg.sender] -= amount;     // 自己的餘額減少
        totalSupply -= amount;              // 總發行量減少
        emit Transfer(msg.sender, address(0), amount); // 轉到 0 地址（代表燒掉了）
    }
}