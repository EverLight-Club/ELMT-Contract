// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import './ERC721Enumerable.sol';
import './Ownable.sol';
import './utils/Strings.sol';

import './interfaces/IELMT.sol';
import './interfaces/IELMTMetadata.sol';
import "./interfaces/IERC721Proxy.sol";
import "./interfaces/IEverLight.sol";

contract ELMT is ERC721Enumerable, Ownable, IELMT, IELMTMetadata {
  using Strings for uint256;
  

  uint256 public constant MIN_STAKING_POWER = 1000; 
  uint256 public constant REDUCE_WINNING_PR = 1; // 1%
  uint256 public constant MIN_WINNING_PR = 7;    // 7%
  uint256 public constant BASE_WINNING_PR = 33;  // 33%
  uint256 public constant MINING_BASE = 2000 * 7200;        // 4h * 60m * 60s / 2 = bncount
  uint256 public constant MIN_MINING_CYCLE_TIME = 2700;     // 1.5h * 60m * 60s / 2
  uint256 public constant INTERVAL_BN = 300_000;    // When the block interval reaches this value, the probability of winning is reduced by 1%.

  // Contract address for external references.
  IERC721Proxy public erc721Proxy;       
  IEverLight   public everLight;

  uint256 private lastUpdateBn;
  uint256 private totalPublicSupply;
  uint256 public startWinningPR = 30;  //
  bool    public isActive = false;

  struct StakingInfo {
    bool initial;
    uint256 tokenId;
    uint256 stakeBn;
  }

  mapping(address => mapping(uint256 => StakingInfo)) private _stakingUserList;
  mapping(uint256 => uint256) private _stakingPowerlist;  // tokenId => power

  string private _contractURI = '';
  string private _tokenBaseURI = '';
  string private _tokenRevealedBaseURI = '';

  event StakeEvent(address indexed from, uint256 characterId, uint256 power, uint256 stakeBn);
  event RedeemEvent(address indexed from, uint256 characterId, uint256 redeemBn, uint256 pb);

  constructor(string memory name, string memory symbol, address proxyAddr, address everLightAddr) ERC721(name, symbol) {
    erc721Proxy = IERC721Proxy(proxyAddr);
    everLight = IEverLight(everLightAddr);
    lastUpdateBn = block.number;    // init blocknumber
  }

  // 
  function stake(uint256 tokenId) external override {
    require(isActive, 'Contract is not active');
    require(address(erc721Proxy) != address(0x0), "erc721Proxy not setting");
    require(address(everLight) != address(0x0), "everLight not setting");
    require(erc721Proxy.ownerOf(tokenId) == msg.sender, "tokenId no owner");

    // check: the type for tokenId(1-character,2-parts, 3-luckStone)

    uint256 tokenType = everLight.queryTokenType(tokenId);
    require(tokenType == 1, "Not be character");
    (, , , uint32 totalPower ) = everLight.queryCharacter(tokenId);
    require(totalPower >= MIN_STAKING_POWER, "Insufficient power");

    // check: execute transfer 
    _transferERC721(address(erc721Proxy), msg.sender, address(this), tokenId);

    _stakingUserList[msg.sender][tokenId] = StakingInfo(true, tokenId, block.number);
    _stakingPowerlist[tokenId] = totalPower;

    emit StakeEvent(msg.sender, tokenId, totalPower, block.number);
  }

  // 
  function redeem(uint256 tokenId) external override {
    require(isActive, 'Contract is not active');
    require(_stakingUserList[msg.sender][tokenId].tokenId == tokenId, "invalid tokenId");
    require(_stakingUserList[msg.sender][tokenId].initial, "already redeem");
    require(erc721Proxy.ownerOf(tokenId) == address(this), "not owner for contract");

    uint256 currentBn = block.number;
    uint256 currentWinningPR = BASE_WINNING_PR;
    uint256 diffBn = currentBn - lastUpdateBn;
    if(diffBn >= INTERVAL_BN) {
       // Probability value of the current effect.
       if(REDUCE_WINNING_PR * (diffBn / INTERVAL_BN) <= currentWinningPR){
         currentWinningPR = currentWinningPR - REDUCE_WINNING_PR * (diffBn / INTERVAL_BN);
       } else {
         currentWinningPR = MIN_WINNING_PR;
       }
      //lastUpdateBn = currentBn;
    }
    if(currentWinningPR < MIN_WINNING_PR){
      currentWinningPR = MIN_WINNING_PR;
    }

    // Calculate how many times the current user pledged computing power can be swiped.
    uint256 singleCyleTime = MINING_BASE / _stakingPowerlist[tokenId]; 
    uint256 stakeTotalBn = currentBn - _stakingUserList[msg.sender][tokenId].stakeBn;
    uint256 times = stakeTotalBn / singleCyleTime;

    if(times > 0){
      for(uint8 i = 0; i < times; i++){
        uint256 random = _getRandom(uint256(i).toString()) % 100;
        if(random <= currentWinningPR){
          totalPublicSupply += 1;
          _safeMint(msg.sender, totalPublicSupply);
        }
      }
    }

    // transfer character
    _transferERC721(address(erc721Proxy), address(this), msg.sender, tokenId);
    
    delete _stakingUserList[msg.sender][tokenId];
    delete _stakingPowerlist[tokenId];

    emit RedeemEvent(msg.sender, tokenId, block.number, currentWinningPR);

  }

  function setIsActive(bool _isActive) external override onlyOwner {
    isActive = _isActive;
  }

  function withdraw() external override onlyOwner {
    uint256 balance = address(this).balance;

    payable(msg.sender).transfer(balance);
  }

  function setContractURI(string calldata URI) external override onlyOwner {
    _contractURI = URI;
  }

  function setBaseURI(string calldata URI) external override onlyOwner {
    _tokenBaseURI = URI;
  }

  function setRevealedBaseURI(string calldata revealedBaseURI) external override onlyOwner {
    _tokenRevealedBaseURI = revealedBaseURI;
  }

  function contractURI() public view override returns (string memory) {
    return _contractURI;
  }

  function rules() public pure override returns (string memory) {
    // rules: {"minPower": MIN_STAKING_POWER, "curPR": currentWinningPR, "desc":""}
    string memory output = string(abi.encodePacked('{"minPower":"', MIN_STAKING_POWER.toString(), '",'));
    //output = string(abi.encodePacked(output, '"curPR":', '"', currentWinningPR.toString(), '",'));
    output = string(abi.encodePacked(output, '"desc":', '"', 'The higher the arithmetic power, the more times you receive NFT, the higher the probability of winning', '"}'));
    return output;
  }

  function tokenURI(uint256 tokenId) public view override(ERC721) returns (string memory) {
    require(_exists(tokenId), 'Token does not exist');
    return bytes(_tokenRevealedBaseURI).length > 0 ?
      string(abi.encodePacked(_tokenRevealedBaseURI, tokenId.toString())) :
      _tokenBaseURI;
  }

  function _transferERC721(address contractAddress, address from, address to, uint256 tokenId) internal {
    address ownerBefore = IERC721(contractAddress).ownerOf(tokenId);
    require(ownerBefore == from, "Not own token");
    
    IERC721(contractAddress).transferFrom(from, to, tokenId);

    address ownerAfter = IERC721(contractAddress).ownerOf(tokenId);
    require(ownerAfter == to, "Transfer failed");
  }

  function _getRandom(string memory purpose) internal view returns (uint256) {
    return uint256(keccak256(abi.encodePacked(block.timestamp, tx.gasprice, tx.origin, purpose)));
  }

}