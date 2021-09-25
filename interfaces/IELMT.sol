// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IELMT {

  function setIsActive(bool isActive) external;

  function withdraw() external;

  function rules() external view returns (string memory);

  function stake(uint256 tokenId) external;

  function redeem(uint256 tokenId) external;
}