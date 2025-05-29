// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract DecentralizedCarRental {

    uint256 public nextCarId;
    uint256 public nextRentalId;

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
        bool isOnline;
        string imageURL;
        string phone;     
    }

    struct RentalInfo {
        uint256 rentalId;
        address payable renter;
        uint256 startTimestamp;
        uint256 endTimestamp;
        uint256 ftotalCost;
        bool isActive;
        bool renterConfirmed;
        bool ownerConfirmed;
        bool extraFeePaid;
    }

    mapping(uint256 => Car) public cars;       // 車輛資料
    mapping(uint256 => RentalInfo) public rentals;  // 租借紀錄
    mapping(address => uint256[]) public ownerToCarIds; // 車主擁有的車輛 IDs
    mapping(uint256 => RentalInfo) public rentalDetails; // 租約 ID 對應租借詳情
    mapping(uint256 => uint256) public carIdToRentalId;  // 車 ID 對應最新的租約 ID
    mapping(address => uint256[]) public renterToRentalIds; // 租客擁有的租借 IDs
    mapping(uint256 => uint256) public rentToCarId;

    // 事件
    event CarListed(uint256 carId, address indexed owner, string model, string plate, uint256 pricePerHour);
    event CarAvailabilityUpdated(uint256 carId, bool isOnline);
    event CarRented(uint256 carId, address indexed renter, uint256 rentstart, uint256 rentend, uint256 totalCost);
    event RentalStart(uint256 carId, address indexed renter);
    event RentalEnded(uint256 carId, address indexed renter);
    event ExtraCharged(uint256 carId, address renter, uint256 extraHours, uint256 extraCost);
    event RentalCancelled(uint256 rentalId, address indexed renter, uint256 refundedAmount);

    // -------------------
    // 車主功能
    // -------------------

    /// 車主上架車輛
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
                isOnline: true,
                imageURL: _imageURL,
                phone: _phone
            });
        ownerToCarIds[msg.sender].push(nextCarId);
        emit CarListed(nextCarId, msg.sender, _model, _plate, _pricePerHour);

        nextCarId++;
    }


    /// 車主下架車輛
    function setCarAvailability(uint256 _carId, bool _isOnline) external {
        Car storage car = cars[_carId];
        require(car.owner == msg.sender, "Not the car owner");
        car.isOnline = _isOnline;
        emit CarAvailabilityUpdated(_carId, _isOnline);
    }

    // -------------------
    // 租客功能
    // -------------------

    /// 租客租借車輛
    function rentCar(uint256 _carId, uint256 totalCost, uint256 rentstart, uint256 rentend) external payable{
        Car storage car = cars[_carId];
        require(car.isOnline, "Car is not available");
        require(car.owner != msg.sender, "Owner cannot rent own car");
        require(totalCost >= car.pricePerHour, "Must rent for at least 1 hour");
        require(car.fdcanstart<=rentstart, "car can not be rented");
        require(car.ldcanstart>=rentend, "over the last day can rent");
        require(msg.value >= totalCost, "Insufficient ETH sent");

        uint256 currentRentalId = nextRentalId;

        // 如果付多了就退還多餘的金額
        uint256 overpaid = msg.value - totalCost;
        if (overpaid > 0) {
            payable(msg.sender).transfer(overpaid);
        }

        // 轉帳租金給車主
        car.owner.transfer(totalCost);

        rentals[_carId] = RentalInfo({
            rentalId: currentRentalId,
            renter: payable(msg.sender),
            startTimestamp: rentstart,
            endTimestamp: rentend,
            ftotalCost: totalCost,
            isActive: false,
            renterConfirmed: false,
            ownerConfirmed: false,
            extraFeePaid: false
        });

        rentalDetails[currentRentalId] = rentals[_carId];
        carIdToRentalId[_carId] = currentRentalId;
        renterToRentalIds[msg.sender].push(currentRentalId);
        rentToCarId[nextRentalId] = _carId;
        nextRentalId++;
        car.isOnline=false;
        emit CarRented(_carId, msg.sender, rentstart, rentend, totalCost);
    }

    // 取消租約並退款
    function cancelRental(uint256 _rentalId) external {
        RentalInfo storage rent = rentalDetails[_rentalId];

        require(rent.renter == msg.sender, "Only renter can cancel");
        require(!rent.isActive, "Rental already started");
        require(rent.ftotalCost > 0, "Rental already cancelled or does not exist");

        // 退款
        uint256 refundAmount = rent.ftotalCost;
        rent.ftotalCost = 0; 
        payable(msg.sender).transfer(refundAmount);

        // 設為無效
        rent.startTimestamp = 0;
        rent.endTimestamp = 0;
        rent.renter = payable(address(0));

        uint256 carId = rentToCarId[_rentalId];
        cars[carId].isOnline = true;

        // emit event for cancellation
        emit RentalCancelled(_rentalId, msg.sender, refundAmount);
    }

    /// 車主或租客雙方確認開始租借
    function startRental(uint256 _carId) external {
        RentalInfo storage rent = rentals[_carId];
        Car storage car = cars[_carId];

        require(
            msg.sender == car.owner || msg.sender == rent.renter,
            "Only renter or owner can confirm start"
        );

        // 各自紀錄確認狀態
        if (msg.sender == rent.renter) {
            rent.renterConfirmed = true;
        } else if (msg.sender == car.owner) {
            rent.ownerConfirmed = true;
        }

        // 當雙方都確認，正式開始租借
        if (rent.renterConfirmed && rent.ownerConfirmed) {
            rent.isActive = true;
            emit RentalStart(_carId, rent.renter);
        }
    }

    // 結束租約且確認是否收取超時費用
    function endRental(uint256 _carId, uint256 overtimeHours) external payable {
        RentalInfo storage rent = rentals[_carId];
        Car storage car = cars[_carId];

        require(
            msg.sender == car.owner || msg.sender == rent.renter,
            "Only renter or owner can confirm return"
        );
        require(rent.isActive, "No active rental");

        // 未超時即設定為已付款
        if (overtimeHours == 0) {
            rent.extraFeePaid = true;
            if (msg.value > 0) {
            payable(msg.sender).transfer(msg.value);
        }
        }

        if (!rent.extraFeePaid) {
        require(msg.sender == rent.renter, "Renter need to pay extra fee");
        }

        // 如果有超時且未付款，要求付款
        if (overtimeHours > 0 && !rent.extraFeePaid) {
            uint256 extraCost = overtimeHours * car.pricePerHour;
            require(msg.value >= extraCost, "Insufficient ETH for overtime");
            // 如果付超過，退還
            uint256 refund = msg.value - extraCost;
            if (refund > 0) {
                payable(msg.sender).transfer(refund);
            }

            // 將超時費轉給車主
            car.owner.transfer(extraCost);

            rent.ftotalCost += extraCost;
            rent.extraFeePaid = true;
            emit ExtraCharged(_carId, rent.renter, overtimeHours, extraCost);
        }

        // 記錄雙方按確認
        if (msg.sender == rent.renter) {
            rent.renterConfirmed = false;
        } else if (msg.sender == car.owner) {
            rent.ownerConfirmed = false;
        }

        if (!rent.renterConfirmed && !rent.ownerConfirmed && rent.extraFeePaid) {
            rent.isActive = false;
            emit RentalEnded(_carId, rent.renter);
        }
        car.isOnline=true;
    }

    // -------------------
    // 查詢功能
    // -------------------

    // 取得某個車主的所有車
    function getMyCars() external view returns (Car[] memory) {
        uint256[] memory myCarIds = ownerToCarIds[msg.sender];
        Car[] memory myCars = new Car[](myCarIds.length);

        for (uint256 i = 0; i < myCarIds.length; i++) {
            myCars[i] = cars[myCarIds[i]];
        }
        return myCars;
    }

    /// 取得某輛車的詳細資料
    function getCar(uint256 _carId) external view returns (Car memory) {
        return cars[_carId];
    }

    /// 取得租借資訊
    function getRentalById(uint256 _rentalId) external view returns (RentalInfo memory) {
        return rentalDetails[_rentalId];
    }

    ///租車人取得自己的租約資訊
    function getMyRentals() external view returns (RentalInfo[] memory) {
        uint256[] memory rentalIds = renterToRentalIds[msg.sender];
        RentalInfo[] memory myRentals = new RentalInfo[](rentalIds.length);

        for (uint256 i = 0; i < rentalIds.length; i++) {
            myRentals[i] = rentalDetails[rentalIds[i]];
        }
        return myRentals;
    }

    /// 查詢可租借的車 ID
    function getAvailableCars() external view returns (uint256[] memory) {
        uint256 availableCount = 0;

        for (uint256 i = 0; i < nextCarId; i++) {
            if (cars[i].isOnline) {
                availableCount++;
            }
        }

        uint256[] memory result = new uint256[](availableCount);
        uint256 index = 0;

        for (uint256 i = 0; i < nextCarId; i++) {
            if (cars[i].isOnline) {
                result[index] = i;
                index++;
            }
        }
        return result;
    }
}
