pragma solidity ^0.4.23;


import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";
// import "../node_modules/openzeppelin-solidity/contracts/payment/PullPayment.sol";
import "../node_modules/openzeppelin-solidity/contracts/ReentrancyGuard.sol";
import "../node_modules/openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "../node_modules/openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";


contract AdvancedPullPayment is ReentrancyGuard {
    
    using SafeMath for uint256;

    // event Withdraw(address indexed _payee, uint256 _payment);
    event DepositUpdated(address indexed _payee, uint256 _payment);

    mapping(address => uint256) public payments;
    // uint256 public totalPayments;

    /**
    * @dev Withdraw accumulated balance, called by payee.
    */
    function withdraw(uint256 amount) public nonReentrant {
        require(amount != 0);

        address payee = msg.sender;
        uint256 payment = payments[payee];

        require(payment != 0);
        require(payment >= amount && address(this).balance >= amount);

        // totalPayments = totalPayments.sub(payment);
        uint256 updated = payment.sub(amount);
        payments[payee] = updated;

        payee.transfer(amount);
        emit DepositUpdated(payee, updated);
    }

    function deposit() public payable nonReentrant {
        require(msg.value != 0);
        asyncSend(msg.sender, msg.value);
    }

    /**
    * @dev Called by the payer to store the sent amount as credit to be pulled.
    * @param dest The destination address of the funds.
    * @param amount The amount to transfer.
    */
    function asyncSend(address dest, uint256 amount) internal {
        uint256 updated = payments[dest].add(amount);
        payments[dest] = updated;
        // totalPayments = totalPayments.add(amount);
        emit DepositUpdated(dest, updated);
    }

    function asyncSendSilently(address dest, uint256 amount) internal {
        payments[dest] = payments[dest].add(amount);
    }

    function asyncTransfer(address src, address dest, uint256 amount) internal {
        uint256 balance = payments[src];
        require(balance >= amount);
        uint256 fromBalance = balance.sub(amount);
        uint256 toBalance = payments[dest].add(amount);
        payments[src] = fromBalance;
        payments[dest] = toBalance;
        emit DepositUpdated(src, fromBalance);
        emit DepositUpdated(dest, toBalance);
    }

}


contract ERC20TokenExchange is AdvancedPullPayment {

    using SafeMath for uint256;

    event SellOrderPut(address indexed _erc20TokenAddress, address indexed _seller, uint256 _tokenPerLot, uint256 _pricePerLot, uint256 _numOfLot);
    event SellOrderFilled(address indexed _erc20TokenAddress, address indexed _seller, address indexed _buyer, uint256 _tokenPerLot, uint256 _pricePerLot, uint256 _numOfLot);

    event BuyOrderPut(address indexed _erc20TokenAddress, address indexed _buyer, uint256 _tokenPerLot, uint256 _pricePerLot, uint256 _numOfLot);
    event BuyOrderFilled(address indexed _erc20TokenAddress, address indexed _buyer, address indexed _seller, uint256 _tokenPerLot, uint256 _pricePerLot, uint256 _numOfLot);

    struct Order {

        uint256 tokenPerLot;
        uint256 pricePerLot;
        uint256 numOfLot;

    }

    mapping(address => mapping(address => Order)) public sellOrders;
    mapping(address => mapping(address => Order)) public buyOrders;


    function putSellOrder(address _erc20TokenAddress, uint256 _tokenPerLot, uint256 _pricePerLot, uint256 _lotToSell) public nonReentrant {

        require(_erc20TokenAddress != address(0));
        require(_tokenPerLot != 0);
        require(_pricePerLot != 0);
        require(_lotToSell != 0);

        address seller = msg.sender;
        Order storage order = sellOrders[_erc20TokenAddress][seller];
        order.tokenPerLot = _tokenPerLot;
        order.pricePerLot = _pricePerLot;
        order.numOfLot = _lotToSell;

        ERC20 erc20 = ERC20(_erc20TokenAddress);
        require(hasSufficientTokenInternal(erc20, seller, _lotToSell.mul(_tokenPerLot)));

        emit SellOrderPut(_erc20TokenAddress, seller, _tokenPerLot, _pricePerLot, _lotToSell);
    }

    function fillSellOrder(address _erc20TokenAddress, address _seller, uint256 _tokenPerLot, uint256 _pricePerLot, uint256 _lotToBuy) public payable nonReentrant {

        require(_erc20TokenAddress != address(0));
        require(_seller != address(0));
        require(_lotToBuy != 0);

        Order storage order = sellOrders[_erc20TokenAddress][_seller];
        require(order.tokenPerLot == _tokenPerLot);
        require(order.pricePerLot == _pricePerLot);
        uint256 numOfLot = order.numOfLot;
        require(numOfLot >= _lotToBuy);

        uint256 payment = _pricePerLot.mul(_lotToBuy);
        require(payment != 0);
        address buyer = msg.sender;
        uint256 cash = msg.value;

        if (payment < cash) {
            asyncSend(_seller, payment);
            asyncSend(buyer, cash.sub(payment));
        } else if (payment == cash) {
            asyncSend(_seller, payment);
        } else {
            if (cash != 0) {
                asyncSendSilently(buyer, cash);
            }
            asyncTransfer(buyer, _seller, payment);
        }

        order.numOfLot = numOfLot.sub(_lotToBuy);

        uint256 amoutToBuy = _lotToBuy.mul(_tokenPerLot);

        ERC20 erc20 = ERC20(_erc20TokenAddress);
        safeSafeTransferFrom(erc20, _seller, buyer, amoutToBuy);
        
        emit SellOrderFilled(_erc20TokenAddress, _seller, buyer, _tokenPerLot, _pricePerLot, _lotToBuy);
    }

    function putBuyOrder(address _erc20TokenAddress, uint256 _tokenPerLot, uint256 _pricePerLot, uint256 _lotToBuy) public payable nonReentrant {

        require(_erc20TokenAddress != address(0));
        require(_tokenPerLot != 0);
        require(_pricePerLot != 0);
        require(_lotToBuy != 0);

        address buyer = msg.sender;
        if (msg.value != 0) {
            asyncSend(buyer, msg.value);
        }
        require(hasSufficientPaymentInternal(buyer, _pricePerLot.mul(_lotToBuy)));            

        Order storage order = buyOrders[_erc20TokenAddress][buyer];
        order.tokenPerLot = _tokenPerLot;
        order.pricePerLot = _pricePerLot;
        order.numOfLot = _lotToBuy;

        emit BuyOrderPut(_erc20TokenAddress, buyer, _tokenPerLot, _pricePerLot, _lotToBuy);
    }

    function fillBuyOrder(address _erc20TokenAddress, address _buyer, uint256 _tokenPerLot, uint256 _pricePerLot, uint256 _lotToSell) public nonReentrant {
        require(_erc20TokenAddress != address(0));
        require(_buyer != address(0));
        require(_tokenPerLot != 0);
        require(_pricePerLot != 0);
        require(_lotToSell != 0);

        Order storage order = buyOrders[_erc20TokenAddress][_buyer];
        uint256 numOfLot = order.numOfLot;

        require(numOfLot >= _lotToSell);
        require(order.tokenPerLot == _tokenPerLot);
        require(order.pricePerLot == _pricePerLot);

        uint256 payment = _pricePerLot.mul(_lotToSell);

        address seller = msg.sender;
        asyncTransfer(_buyer, seller, payment);
        order.numOfLot = numOfLot.sub(_lotToSell);

        ERC20 erc20 = ERC20(_erc20TokenAddress);

        uint256 amoutToSell = _lotToSell.mul(_tokenPerLot);
        safeSafeTransferFrom(erc20, seller, _buyer, amoutToSell);

        emit BuyOrderFilled(_erc20TokenAddress, _buyer, seller, _tokenPerLot, _pricePerLot, _lotToSell);
    }

    function safeSafeTransferFrom(ERC20 _erc20, address _from, address _to, uint256 _amount) internal {
        uint256 previousBalance = _erc20.balanceOf(_to);        
        SafeERC20.safeTransferFrom(_erc20, _from, _to, _amount);
        require(previousBalance.add(_amount) == _erc20.balanceOf(_to));
    }

    function isValidSellOrder(address _erc20TokenAddress, address _seller) public view returns(bool) {
        ERC20 erc20 = ERC20(_erc20TokenAddress);
        Order storage order = sellOrders[_erc20TokenAddress][_seller];
        return hasSufficientTokenInternal(erc20, _seller, order.tokenPerLot.mul(order.numOfLot));
    }

    function isValidBuyOrder(address _erc20TokenAddress, address _buyer) public view returns(bool) {
        Order storage order = buyOrders[_erc20TokenAddress][_buyer];
        return hasSufficientPaymentInternal(_buyer, order.pricePerLot.mul(order.numOfLot));
    }

    function getSellOrderInfo(address _erc20TokenAddress, address _seller) public view returns(uint256, uint256, uint256) {
        Order storage order = sellOrders[_erc20TokenAddress][_seller];
        return (order.tokenPerLot, order.pricePerLot, order.numOfLot);
    }

    function getBuyOrderInfo(address _erc20TokenAddress, address _buyer) public view returns(uint256, uint256, uint256) {
        Order storage order = buyOrders[_erc20TokenAddress][_buyer];
        return (order.tokenPerLot, order.pricePerLot, order.numOfLot);
    }

    function hasSufficientPaymentInternal(address _payee, uint256 _amount) internal view returns(bool) {
        return payments[_payee] >= _amount;
    }

    function hasSufficientTokenInternal(ERC20 erc20, address _seller, uint256 _amountToSell) internal view returns(bool) {
        return erc20.balanceOf(_seller) >= _amountToSell && erc20.allowance(_seller, address(this)) >= _amountToSell;
    }

}