// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract DecentralizedCarRental {

    uint256 public nextCarId;

    struct Car {
        uint256 carId;
        bool isscooter;
        address payable owner;
        string locate;
        string model;
        string plate;
        uint256 pricePerHour;
        uint256 fdcanstart;
        uint256 ldcanstart;
        uint256 status;   // 1: 可出租, 2: 已被預約, 3: 正在出租, 4: 結束租約, 5: 下架
        string imageURL;
        string phone;     
    }

    struct RentalInfo {
        uint256 carId;    
        address payable renter;
        uint256 startTimestamp;
        uint256 endTimestamp;
        uint256 ftotalCost;
        bool isActive;
        bool renterConfirmed;
        bool ownerConfirmed;
        bool extraFeePaid;
    }
    
    mapping(uint256 => Car) public cars;       
    mapping(uint256 => RentalInfo) public rentals;  
    mapping(address => uint256[]) public ownerToCarIds; 
    mapping(uint256 => RentalInfo) public rentalDetails; 
    mapping(address => uint256[]) public renterToCarIds; 

    event CarListed(uint256 carId, address indexed owner, string model, string plate, uint256 pricePerHour);
    event Caroffline(uint256 carId);
    event CarRented(uint256 carId, address indexed renter, uint256 rentstart, uint256 rentend, uint256 totalCost);
    event RentalStart(uint256 carId, address indexed renter);
    event RentalEnded(uint256 carId, address indexed renter);
    event ExtraCharged(uint256 carId, address renter, uint256 extraHours, uint256 extraCost);
    event RentalCancelled(uint256 carId, address indexed renter, uint256 refundedAmount);

    // 車主功能

    // 上傳車輛
    function addCar(
        bool _isscooter,
        string memory _locate,
        string memory _model,
        string memory _plate,
        uint256 _pricePerHour,
        uint256 _fdcanstart,
        uint256 _ldcanstart,
        string memory _imageURL,
        string memory _phone
        ) external {
            require(_pricePerHour > 0, "Price must be greater than zero");
            require(_ldcanstart > _fdcanstart, "lastday must be after firstday");

            cars[nextCarId] = Car({
                carId: nextCarId,
                isscooter: _isscooter,
                owner: payable(msg.sender),
                locate: _locate,
                model: _model,
                plate: _plate,
                fdcanstart: _fdcanstart,
                ldcanstart: _ldcanstart,
                pricePerHour: _pricePerHour,
                status: 1,
                imageURL: _imageURL,
                phone: _phone
            });
        ownerToCarIds[msg.sender].push(nextCarId);
        emit CarListed(nextCarId, msg.sender, _model, _plate, _pricePerHour);

        nextCarId++;
    }

    // 下架車輛
    function setCarAvailability(uint256 _carId) external {
        Car storage car = cars[_carId];
        require(car.status == 1, "Can't change your car status");
        require(car.owner == msg.sender, "Not the car owner");
        car.status = 5;
        emit Caroffline(_carId);
    }

    // 租客功能

    // 租車
    function rentCar(uint256 _carId, uint256 totalCost, uint256 rentstart, uint256 rentend) external payable {
        Car storage car = cars[_carId];
        require(car.status == 1, "Car is not available");
        require(car.owner != msg.sender, "Owner cannot rent own car");
        require(totalCost >= car.pricePerHour, "Must rent for at least 1 hour");
        require(msg.value >= totalCost, "Insufficient ETH sent");

        // 退還超過的費用
        uint256 overpaid = msg.value - totalCost;
        if (overpaid > 0) {
            payable(msg.sender).transfer(overpaid);
        }

        // 轉帳
        car.owner.transfer(totalCost);

        rentals[_carId] = RentalInfo({
            carId: _carId, 
            renter: payable(msg.sender),
            startTimestamp: rentstart,
            endTimestamp: rentend,
            ftotalCost: totalCost,
            isActive: false,
            renterConfirmed: false,
            ownerConfirmed: false,
            extraFeePaid: false
        });

        rentalDetails[_carId] = rentals[_carId];
        renterToCarIds[msg.sender].push(_carId); 
        car.status = 2;
        emit CarRented(_carId, msg.sender, rentstart, rentend, totalCost);
    }

    // 取消租約
    function cancelRental(uint256 _carId) external {
        RentalInfo storage rent = rentalDetails[_carId];

        require(rent.renter == msg.sender, "Only renter can cancel");
        require(!rent.isActive, "Rental already started");
        require(rent.ftotalCost > 0, "Rental already cancelled or does not exist");

        // 退款
        uint256 refundAmount = rent.ftotalCost;
        rent.ftotalCost = 0; 
        payable(msg.sender).transfer(refundAmount);

        // 重置
        rent.startTimestamp = 0;
        rent.endTimestamp = 0;
        rent.renter = payable(address(0));

        cars[_carId].status = 1;
        emit RentalCancelled(_carId, msg.sender, refundAmount);
    }

    // 確認開始租車
    function startRental(uint256 _carId) external {
        RentalInfo storage rent = rentals[_carId];
        Car storage car = cars[_carId];

        require(
            msg.sender == car.owner || msg.sender == rent.renter,
            "Only renter or owner can confirm start"
        );
        require(car.status == 2, "Car has not been rented");

        // 更改狀態
        if (msg.sender == rent.renter) {
            rent.renterConfirmed = true;
        } else if (msg.sender == car.owner) {
            rent.ownerConfirmed = true;
        }

        // 若雙方都確認即開始
        if (rent.renterConfirmed && rent.ownerConfirmed) {
            rent.isActive = true;
            car.status = 3;
            emit RentalStart(_carId, rent.renter);
        }
    }

    // 結束租約並計算超時費用
    function endRental(uint256 _carId, uint256 overtimeHours) external payable {
        RentalInfo storage rent = rentals[_carId];
        Car storage car = cars[_carId];
        require(car.status == 3, "Car is not currently rented");
        require(msg.sender == car.owner || msg.sender == rent.renter,"Only renter or owner can confirm return");
        require(rent.isActive, "No active rental");

        // 若沒有超時即為已付款
        if (overtimeHours == 0) {
            rent.extraFeePaid = true;
            if (msg.value > 0) {
                payable(msg.sender).transfer(msg.value);
            }
        }

        if (!rent.extraFeePaid) {
            require(msg.sender == rent.renter, "Renter needs to pay extra fee");
        }

        // 支付費用
        if (overtimeHours > 0 && !rent.extraFeePaid) {
            uint256 extraCost = overtimeHours * car.pricePerHour;
            require(msg.value >= extraCost, "Insufficient ETH for overtime");
            uint256 refund = msg.value - extraCost;
            if (refund > 0) {
                payable(msg.sender).transfer(refund);
            }
            // 轉帳
            car.owner.transfer(extraCost);

            rent.ftotalCost += extraCost;
            rent.extraFeePaid = true;
            emit ExtraCharged(_carId, rent.renter, overtimeHours, extraCost);
        }

        // 確認雙方都確認好即為還車成功
        if (msg.sender == rent.renter) {
            rent.renterConfirmed = false;
        } else if (msg.sender == car.owner) {
            rent.ownerConfirmed = false;
        }
        if (!rent.renterConfirmed && !rent.ownerConfirmed && rent.extraFeePaid) {
            rent.isActive = false;
            car.status = 4;
            emit RentalEnded(_carId, rent.renter);
        }
    }

    // -------------------
    // 查詢功能
    // -------------------

    // 車主取得自己的所有車輛
    function getMyCars() external view returns (Car[] memory) {
        uint256[] memory myCarIds = ownerToCarIds[msg.sender];
        Car[] memory myCars = new Car[](myCarIds.length);
        for (uint256 i = 0; i < myCarIds.length; i++) {
            myCars[i] = cars[myCarIds[i]];
        }
        return myCars;
    }

    /// 車輛細節
    function getCar(uint256 _carId) external view returns (Car memory) {
        return cars[_carId];
    }

    /// 透過車子id查詢租約細節
    function getRentalById(uint256 _carId) external view returns (RentalInfo memory) {
        return rentalDetails[_carId];
    }

    /// 租客查詢自己的所有租約資訊
    function getMyRentals() external view returns (RentalInfo[] memory) {
        uint256[] memory carIds = renterToCarIds[msg.sender];
        RentalInfo[] memory myRentals = new RentalInfo[](carIds.length);
        for (uint256 i = 0; i < carIds.length; i++) {
            myRentals[i] = rentalDetails[carIds[i]];
        }
        return myRentals;
    }

    /// 查詢所有可租車輛
    function getAvailableCars() external view returns (uint256[] memory) {
        uint256 availableCount = 0;
        for (uint256 i = 0; i < nextCarId; i++) {
            if (cars[i].status == 1) {
                availableCount++;
            }
        }
        uint256[] memory result = new uint256[](availableCount);
        uint256 index = 0;
        for (uint256 i = 0; i < nextCarId; i++) {
            if (cars[i].status == 1) {
                result[index] = i;
                index++;
            }
        }
        return result;
    }
}