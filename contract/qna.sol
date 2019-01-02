pragma solidity ^0.5.0;

contract QnA {
    /*
        Local vars
    */
    address private owner;
    mapping (address => User) public members;
    Question[] public questions;
    Comment[] public comments;
    uint32 donate_ratio;
    
    /*
        Structs
    */
    struct User {
        uint received_val;
        uint32[] ownQuestion;
        uint32[] ownComment;
        // More attributes?
    }

    struct Question {
        address payable owner;
        uint value;
        string title;
        // TODO: 改成ipfs/swarm hash
        string content;
        uint32[] comments;
        bool isAnswered;
        uint32 acceptedAnswer;
        uint received_val;
        uint time;
    }

    struct Comment {
        address payable owner;
        // 紀錄所屬問題
        uint32 questionId;
        // 階層式留言，目前設定這個值是uint32最大值的話為回答，其他為留言，只有回答能被接受
        uint32 parentId;
        // TODO: 改成ipfs/swarm hash
        string content;
        uint received_val;
        uint time;
    }
    
    /*
        Events
    */
    event questionAsked(address user, uint32 qId);
    event answerAdded(address user, uint32 qId, uint32 cId);
    event commentAdded(address user, uint32 qId, uint32 pcId, uint32 cId);
    event questionAnswered(uint32 qId, uint32 cId, uint reward);
    event commentDonated(uint32 cId, address donator, uint value);
    event questionDonated(uint32 qId, address donator, uint value);
    
    /*
        Modifiers
    */
    modifier onlyOwner() {
        require(owner == msg.sender, "you are not owner");
        _;
    }

    // 建構子
    constructor() public payable {
        donate_ratio = 10;
        owner = msg.sender;
    }
    
    /*
        Private Functions
    */
    
    function uint32Max() private pure returns (uint32) {
        uint32 i = 0;
        return i - 1;
    }
    
    function transferAndRecordForComment(uint value, uint32 cId) private {
        address payable addr = comments[cId].owner;
        addr.transfer(value);
        comments[cId].received_val += value;
        members[addr].received_val += value;
    }
    
    function transferAndRecordForQuestion(uint value, uint32 qId) private {
        address payable addr = questions[qId].owner;
        addr.transfer(value);
        questions[qId].received_val += value;
        members[addr].received_val += value;
    }
    
    function commentFactory(uint32 qId, string memory content, uint32 pcId) private returns (uint32) {
        // 製造新的comment並且加進comment array
        Comment memory newCom;
        newCom.owner = msg.sender;
        newCom.questionId = qId;
        newCom.parentId = pcId;
        newCom.content = content;
        newCom.received_val = 0;
        newCom.time = now;
        uint32 cId = uint32(comments.length);
        comments.push(newCom);
        return cId;
    }
    
    /*
        Public Functions
    */
    
    function changeDonateRatio(uint32 ratio) public onlyOwner {
        donate_ratio = ratio;
    }
    
    function askQuestion(string memory title, string memory content) public payable {
        require(msg.value > 0, "You need to give reward!");
        // new a question
        Question memory newQ;
        newQ.owner = msg.sender;
        newQ.value = msg.value;
        newQ.title = title;
        newQ.content = content;
        newQ.time = now;
        // recored BEFORE append question(qId start from 0)
        uint32 qId = uint32(questions.length);
        questions.push(newQ);
        // Add connection between user and question
        members[msg.sender].ownQuestion.push(qId);
        // Emit event
        emit questionAsked(msg.sender, qId);
    }
    
    function addAnswer(uint32 questionId, string memory content) public {
        require(questionId < questions.length, "Question not found!");
        // new a Comment
        uint32 cId = commentFactory(questionId, content, uint32Max());
        // Add connection between user and comment, comment and question
        questions[questionId].comments.push(cId);
        members[msg.sender].ownComment.push(cId);
        // Emit event
        emit answerAdded(msg.sender, questionId, cId);
    }
    
    function addComment(uint32 questionId, uint32 parentCommentId, string memory content) public {
        require(questionId < questions.length, "Question not found!");
        require(parentCommentId < comments.length, "Parent comment not found!");
        require(parentCommentId != uint32Max(), "This is not an answer!");
        // new a Comment
        uint32 cId = commentFactory(questionId, content, parentCommentId);
        // Add connection between user and comment, comment and question
        questions[questionId].comments.push(cId);
        members[msg.sender].ownComment.push(cId);
        // Emit event
        emit commentAdded(msg.sender, questionId, parentCommentId, cId);
    }
    
    function acceptAnswer(uint32 questionId, uint32 commentId) public {
        Question storage Q = questions[questionId];
        Comment memory A = comments[commentId];
        require(!Q.isAnswered, "This question already answered.");
        require(Q.owner == msg.sender, "You cannot accept answer!");
        require(questionId < questions.length, "Question not found!");
        require(commentId < comments.length, "Comment not found!");
        require(A.parentId == uint32Max(), "You cannot accept a comment!");
        require(A.questionId == questionId, "Wrong questionId for comment!");
        // Give accepted answer question value
        uint reward = questions[questionId].value;
        // comments[commentId].owner.transfer(reward);
        transferAndRecordForComment(reward, commentId);
        // Mark this question as answered
        Q.isAnswered = true;
        Q.acceptedAnswer = commentId;
        // Emit event
        emit questionAnswered(questionId, commentId, reward);
    }
    
    function donateComment(uint32 commentId) public payable {
        require(commentId < comments.length, "Comment not found!");
        // 計算該給發問者跟回答者的斗內
        uint toCommentMaker = (msg.value * (donate_ratio - 1)) / donate_ratio;
        uint toQuestionMaker = msg.value - toCommentMaker; // 因為沒有浮點數所以用減的
        
        // 分別轉帳給發問者跟回答者
        // 紀錄收到多少斗內
        transferAndRecordForComment(toCommentMaker, commentId);
        uint32 qId = comments[commentId].questionId;
        transferAndRecordForQuestion(toQuestionMaker, qId);
        
        // Emit event
        emit commentDonated(commentId, msg.sender, toCommentMaker);
        emit questionDonated(qId, msg.sender, toQuestionMaker);
    }
    
    function donateQuestion(uint32 questionId) public payable {
        require(questionId < questions.length, "Question not found!");
        transferAndRecordForQuestion(msg.value, questionId);
        // Emit event
        emit questionDonated(questionId, msg.sender, msg.value);
    }
    
    // getters
    function getAllQuestionIdByAddr(address addr) public view returns (uint32[] memory) {
        return members[addr].ownQuestion;
    }
    
    function getAllCommentIdByAddr(address addr) public view returns (uint32[] memory) {
        return members[addr].ownComment;
    }
}