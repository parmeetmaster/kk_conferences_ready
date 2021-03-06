import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:kk_conferences/api/FirbaseApi.dart';
import 'package:kk_conferences/api/web_api/razorpay_payment.dart';
import 'package:kk_conferences/global/Global.dart';
import 'package:kk_conferences/global/const_funcitons.dart';
import 'package:kk_conferences/global/constants.dart';
import 'package:kk_conferences/model/booking_model.dart';
import 'package:kk_conferences/model/carrage_model.dart';
import 'package:kk_conferences/providers/booking_screen_provider.dart';
import 'package:kk_conferences/providers/my_booking_provider.dart';
import 'package:kk_conferences/utils/dialog.dart';
import 'package:kk_conferences/utils/m_progress_indicator.dart';
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:uuid/uuid.dart';

class BookingHelper {
  BuildContext context;
  BookingModel errorModel;
  Razorpay razorpay;
  Carrage carrage;
 static int amountPaidCurruntTransaction;

  getBookings(DateTime date,Carrage carrage) async {

    QuerySnapshot snapshot = await FireBaseCustomersApi().getSelectedDateBookings(
        model: BookingModel(bookingDate: getFirebaseFormatDate(date),roomno: carrage.confressModel.roomNo));
    return snapshot;
  }

  //2
  Future<bool> checkIsBookingExist(
      {TimeOfDay endTime, TimeOfDay startTime, DateTime date}) async {
    print("we called");
    int cuuruntMeetingStartInDuration =
        Duration(hours: startTime.hour, minutes: startTime.minute).inSeconds;
    int cuuruntMeetingEndInDuration =
        Duration(hours: endTime.hour, minutes: endTime.minute).inSeconds;
    QuerySnapshot snapshot = await getBookings(date,carrage);
    for (QueryDocumentSnapshot item in snapshot.docs) {
      BookingModel model = BookingModel.fromJson(item.data());
      if (cuuruntMeetingStartInDuration<model.bookingStartduration
          && model.bookingStartduration<cuuruntMeetingEndInDuration) {

        errorModel = model;
        print("clash of scenerio 1");
        return false;
      } else if (cuuruntMeetingStartInDuration<model.bookingEndduration
          && model.bookingEndduration<cuuruntMeetingEndInDuration) {

        errorModel = model;
        print("clash of scenerio 2");
        return false;
      } else if (
      (cuuruntMeetingStartInDuration>model.bookingStartduration && cuuruntMeetingStartInDuration<model.bookingEndduration )
      && ( cuuruntMeetingStartInDuration<model.bookingEndduration && cuuruntMeetingEndInDuration<model.bookingEndduration )) {
        print("clash of scenerio 3");
        errorModel = model;
        return false;
      } else if (cuuruntMeetingStartInDuration > model.bookingStartduration &&
          cuuruntMeetingEndInDuration < model.bookingEndduration) {
        print("clash of scenerio 4");
        errorModel = model;
        return false;
      }
    }
    return true;
  }

  TimeOfDay startTime;
  TimeOfDay endTime;
  DateTime date;
  double amount;

  // 1
  performBooking(BuildContext context,
      { endTime,
      TimeOfDay startTime,
      DateTime date,
      int hourdifference,Carrage carrage}) async {
    this.context=context;// this for referesh screen

    this.carrage=carrage;

    bool booking_flag = await checkIsBookingExist(
        endTime: endTime, startTime: startTime, date: date );
    // 3
    if (booking_flag == false) {
      DialogUtil(
        context: context,
        message:
            "This Slot is Booked \n From ${getDateWith12HrsFormat(errorModel.bookingStartTime)} To: ${getDateWith12HrsFormat(errorModel.bookingEndTime)}",
        title: "Error Booking Already Exist",
      ).showErrorDialog();
      return;
    }
    this.endTime=endTime;
    this.startTime=startTime;
    this.date=date;
    this.amount=amount;

   await initRazorPay();
   openCheckout( hourdifference,"Booking for ${getFormattedTime(startTime)} to ${getFormattedTime(endTime)} on ${getFirebaseFormatDate(date)}");
  }

  void convertSecondsToTime(int seconds) {
    Duration duration = Duration(seconds: seconds);
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    // return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
    print("${duration.inHours} mins ${twoDigitMinutes} ");
  }

  /*There is payment gateway code */
  void initRazorPay() {
    razorpay = Razorpay();
    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  void openCheckout(int hourdifference, String description) async {
    amountPaidCurruntTransaction=(hourdifference*carrage.confressModel.price);
    var options = {
      'key': appmode==test?razor_id_test:razor_id,
      'amount': (hourdifference*carrage.confressModel.price)*100, // price show here
      'name': '$company_name',
      'description': '$description',
      'prefill': {'contact': ' $phno', 'email': '$email'},
      'external': {
        'wallets': ['paytm']
      },
      'notes':[Global.activeCustomer.toJson()]
    };

    try {
      razorpay.open(options);
    } catch (e) {
      debugPrint(e);
    }
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response)async {
   // MProgressIndicator.show(context);

      print("resp data: ${response.paymentId} ${response.orderId} ${response.signature}");
      final provider=Provider.of<BookingScreenProvider>(context,listen: false);
      provider.showTodayMettings(date, carrage);
      provider.notifyListeners();
      startTime = TimeOfDay(hour: startTime.hour, minute: startTime.minute + 1);
      var uuid = Uuid();
      BookingModel model=BookingModel(
          bookingDate: getFirebaseFormatDate(date),
          bookingStartTime: getDatewithTime(date, startTime),
          bookingEndTime: getDatewithTime(date, endTime),
          bookingStartduration:
          Duration(hours: startTime.hour, minutes: startTime.minute).inSeconds,
          bookingEndduration:
          Duration(hours: endTime.hour, minutes: endTime.minute).inSeconds,
          bookingUserId: Global.activeCustomer.customerId,
          roomno: carrage.confressModel.roomNo,
          roomname: carrage.confressModel.name,
          // todo need to use unique id during login
          bookingId: uuid.v4(),
          bookingStatus: false,
          amount: amountPaidCurruntTransaction.toString(),
          paymentId: response.paymentId,
          orderId: response.orderId,
          signature: response.signature
      );
      await FireBaseCustomersApi().addBookingEntery(
          model: model);
     // await RazorPayPaymentApi().capturePayment(model);
    try{  }catch(e){
      MProgressIndicator.hide();
    }


  }

  void _handlePaymentError(PaymentFailureResponse response) {
    print(
        "code is ${response.code.toString()} response${response.message.toString()}");
    Fluttertoast.showToast(
        msg: "ERROR: " + response.code.toString() + " - " + response.message,
        timeInSecForIosWeb: 4);
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    Fluttertoast.showToast(
        msg: "EXTERNAL_WALLET: " + response.walletName, timeInSecForIosWeb: 4);
  }
}
