$("#ckbCheckAll").click(function () {
    $(".blank-checkbox").prop('checked', $(this).prop('checked'));
});

$("#formSubmit").click(function () {
    $("#userIdForm").submit();
});
