$(".flippable").click(function(){
  $(this).toggleClass("flipme");
});

function pullCard(self, sex) {
    $(".app-loader").show();
    $(self).attr("disabled", "disabled");
    $("#pushCardButton").attr("disabled", "disabled");
    
    $.get("/card/pull", function (data) {
	if (data.status == "success") {
	    $("#pushCardButton").attr("disabled", "disabled");
	    $(".ac-first").parent().animate({left:"-120px"});
	    $(".ac-second").parent().animate({left:"120px"});
	    $(".ac-second > .back").text(data.username);
	    $(".dating-button").attr("onclick", "dating(\'"+ data.username  +"\')");
	    $(".ac-second").parent().show(300);
	    $(".app-actions").show(300);
	    $(".app-loader").hide();
	    if (sex == "male") {
		pullCardMaleCount();
	    } else {
		pullCardFemaleCount();
	    }
	} else {
	    $(".modal-body").text("晚了一步，已经被抽走了!");
	    $(".app-loader").hide();	    
	    $("#dialogMessage").modal('show');
	    $("#pushCardButton").removeAttr("disabled");	    
	    if (sex == "male") {
		pullCardMaleCount();
	    } else {
		pullCardFemaleCount();
	    }	    
	}
    }, "json");
}

function pushCard(self, sex) {
    $(".app-loader").show();
    $(self).attr("disabled", "disabled");
    if (sex == "male") {
	$("#pullFemaleCardButton").attr("disabled", "disabled");
    } else {
	$("#pullMaleCardButton").attr("disabled", "disabled");	
    }
    $.get("/card/push", function (data) {
	if (data.status == "success") {
	    $(self).text("我要退牌");
	    $(self).attr("onclick", "reCard(this, \'"+ sex +"\')");
	    $(self).removeAttr("disabled");
	    $(".ac-first").hide(300);
	    $(".notification-message > h4").text("待约");	    
	    $(".notification-message").show(300);
	    $(".app-loader").hide();
	    if (sex == "male") {
		$(self).attr("id", "reMaleCardButton");
		pullCardMaleCount();
		$("#pullFemaleCardButton").attr("disabled", "disabled");
	    } else {
		$(self).attr("id", "reFemaleCardButton");
		pullCardFemaleCount();
		$("#pullMaleCardButton").attr("disabled", "disabled");
	    }
	} else {
	    $(".modal-body").text("出错了, 刷新试试!");
	    $("#dialogMessage").modal('show');
	    if (sex == "male") {
		$("#pullFemaleCardButton").removeAttr("disabled");
	    } else {
		$("#pullMaleCardButton").removeAttr("disabled");	
	    }
	}
    }, "json");
}

function reCard(self, sex) {
    $(".app-loader").show();
    $(self).attr("disabled", "disabled");    
    $.get("/card/re", function (data) {
	if (data.status == "success") {
	    $(self).text("我要放牌");
	    $(self).attr("id", "pushCardButton");
	    $(self).attr("onclick", "pushCard(this, \'"+ sex +"\')");
	    $(self).removeAttr("disabled");    	    
	    $(".ac-first").show(300);
	    $(".ac-first").parent().show(300);
	    $(".notification-message").hide(300);
	    pullCardMaleCount();
	    pullCardFemaleCount();
	    $(".app-loader").hide();
	} else {
	    $(self).attr("id", "reCardButton");
	    $(".modal-body").text("晚了一步，你已经被抽中了!");
	    $(".app-loader").hide();
	    $("#dialogMessage").modal('show');
	    pullCardMaleCount();
	    pullCardFemaleCount();	    
	}
    }, "json");
}

function pullCardMaleCount() {
    $.get("/card/male/count", function (data) {
	if (data.status == "success") {
	    $("#cardMaleCount").text(data.count);
	    if (data.count == 0) {
		$("#pullMaleCardButton").attr("disabled", "disabled");
		$("#reMaleCardButton").attr("disabled", "disabled");
	    } else if (data.state == 0) {
		$("#pullMaleCardButton").removeAttr("disabled");		
	    } else {
		$("#pullMaleCardButton").attr("disabled", "disabled");		
	    }
	} else {
	    $(".modal-body").text("出错了, 刷新试试!");
	    $("#dialogMessage").modal('show');
	}
    }, "json");
}

function pullCardFemaleCount() {
    $.get("/card/female/count", function (data) {
	if (data.status == "success") {
	    $("#cardFemaleCount").text(data.count)
	    if (data.count == 0) {
		$("#pullFemaleCardButton").attr("disabled", "disabled");
		$("#reFemaleCardButton").attr("disabled", "disabled");
	    } else if (data.state == 0) {
		$("#pullFemaleCardButton").removeAttr("disabled");
	    } else {
		$("#pullFemaleCardButton").attr("disabled", "disabled");
	    }
	}
    }, "json");
}

function haveNotifications() {
    $.get("/notifications/have", function (data) {
	if (data.status == "success" && data.notifications == "yes") {
	    $("#notificationCount").text(data.count);
	}
    }, "json");
}

function isPulled() {
    $.get("/ispulled", function (data) {
	if (data.status == "success" && data.message == "yes") {
	    $(".notification-message > h4").text("有约");
	}
    }, "json");
}


window.setInterval("pullCardMaleCount()", 10000);
window.setInterval("pullCardFemaleCount()", 10000);
window.setInterval("haveNotifications()", 10000);
window.setInterval("isPulled()", 10000);

function sendTeaDialog(self) {
    $("#appSendTeaDialog > .modal-dialog > .modal-content > .modal-body").text("要送五香茶吗?");
    $("#appSendTeaDialog").modal('show');    
}

function datingDialog(self) {
    $("#appDatingDialog > .modal-dialog > .modal-content > .modal-body").text("约吗?");
    $("#appDatingDialog").modal('show');    
}

function sendTea(to) {
    $("#sendTeaButton").attr("disabled", "disabled");
    $("#datingButton").attr("disabled", "disabled");
    $(".app-loader").show();    
    $.get("/action/sendtea", function (data) {
	if (data.status == "success") {
	    haveNotifications();
	    $(".modal-body").text("送茶成功!");
	    $("#dialogMessage").modal('show');
	    $(".app-loader").hide();
	} else {
	    $(".modal-body").text("出错了, 刷新试试!");
	    $("#dialogMessage").modal('show');
	    $("#sendTeaButton").removeAttr("disabled");
	    $("#datingButton").removeAttr("disabled");	    
	}
    }, "json");
}

function dating(to) {
    $("#sendTeaButton").attr("disabled", "disabled");
    $("#datingButton").attr("disabled", "disabled");    
    $(".app-loader").show();
    $.get("/action/dating", function (data) {
	if (data.status == "success") {
	    haveNotifications();
	    $(".modal-body").text("预约成功!");
	    $("#dialogMessage").modal('show');
	    $(".app-loader").hide();
	} else {
	    $(".modal-body").text("出错了, 刷新试试!");
	    $("#dialogMessage").modal('show');
	    $("#sendTeaButton").removeAttr("disabled");
	    $("#datingButton").removeAttr("disabled");	    	    
	}
    }, "json");
}
