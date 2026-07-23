import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/dashboard_controller.dart';

class TranslationService {
  static const Map<String, String> _sinhala = {
    // Navigation / Sidebar
    'Dashboard': 'පුවරුව',
    'Items': 'මෙනු ද්‍රව්‍ය',
    'Dining Tables': 'ආහාර මේස',
    'POS System': 'POS පද්ධතිය',
    'Pre Orders': 'පූර්ව ඇණවුම්',
    'POS Orders': 'POS ඇණවුම්',
    'Queue Screen': 'පෝලිම් තිරය',
    'K.D.S (Kitchen)': 'කුස්සි තිරය (KDS)',
    'Kitchen Display (KDS)': 'කුස්සි දර්ශකය (KDS)',
    'Order Queue Screen': 'ඇණවුම් පෝලිම් තිරය',
    'Offers': 'දීමනා',
    'Administrators': 'පරිපාලකයින්',
    'Delivery Boys': 'බෙදාහරින්නන්',
    'Customers': 'පාරිභෝගිකයින්',
    'Employees': 'සේවකයින්',
    'Waiters': 'වේටර්වරු',
    'Chefs': 'සුපවේදීන්',
    'Short Eats Cabin': 'කෙටි ආහාර කුටිය',
    'Staff Attendance & Salary': 'කාර්ය මණ්ඩල පැමිණීම සහ පඩිය',
    'Sales Report': 'විකුණුම් වාර්තාව',
    'Items Report': 'ද්‍රව්‍ය වාර්තාව',
    'Credit Balance Report': 'ණය ශේෂ වාර්තාව',
    'Shifts & Cash': 'මාරුවීම් සහ මුදල්',
    'Shifts & Drawer': 'මුදල් ලාච්චුව සහ මාරුවීම්',
    'Reports & Logs': 'වාර්තා සහ සටහන්',
    'Settings': 'සැකසුම්',
    'Settings & Stock': 'සැකසුම් සහ තොග',
    'Edit Profile': 'පැතිකඩ සංස්කරණය',
    'Change Password': 'මුරපදය වෙනස් කරන්න',
    'Roles & Permissions': 'භූමිකාවන් සහ අවසර',

    // Section Titles
    'POS & ORDERS': 'POS සහ ඇණවුම්',
    'PROMO': 'ප්‍රවර්ධන',
    'USERS': 'පරිශීලකයින්',
    'REPORTS & SHIFTS': 'වාර්තා සහ මාරුවීම්',
    'STOCKS': 'තොග',
    'SYSTEM': 'පද්ධතිය',

    // Header & User Greeting
    'Good Morning!': 'සුභ උදෑසනක්!',
    'Good Afternoon!': 'සුභ පස්වරුවක්!',
    'Good Evening!': 'සුභ සැන්දෑවක්!',
    'Hello': 'ආයුබෝවන්',
    'Guest User': 'අමුත්තා',
    'English': 'ඉංග්‍රීසි',
    'Sinhala': 'සිංහල',
    'SHIFT OPEN': 'මුදල් මාරුව විවෘතයි',
    'SHIFT CLOSED': 'මුදල් මාරුව වසා ඇත',
    'Online': 'සබැඳි',
    'Offline': 'නොබැඳි',
    'LAN Online': 'LAN සබැඳි',
    'LAN Offline': 'LAN නොබැඳි',
    'Logout': 'පිටවීම',

    // Pre Orders Screen
    'Manage advance bookings, estimates, and customer reservations': 'කල්තියා ඇණවුම්, තක්සේරු සහ පාරිභෝගික වෙන්කිරීම් කළමනාකරණය කරන්න',
    'Create Pre Order': 'පූර්ව ඇණවුමක් සාදන්න',
    'Active Pre-Orders': 'සක්‍රිය පූර්ව ඇණවුම්',
    'History / Converted': 'ඉතිහාසය / ලබා දුන්',
    'Search by Customer, Phone, or Pre Order No...': 'පාරිභෝගිකයා, දුරකථනය හෝ පූර්ව ඇණවුම් අංකයෙන් සොයන්න...',
    'No pre orders found': 'පූර්ව ඇණවුම් හමු නොවීය',
    'Pre Order loaded into POS cart. Proceed to checkout.': 'පූර්ව ඇණවුම POS කාර්ට් එකට ඇතුළත් විය. ගෙවීමට ඉදිරියට යන්න.',
    'Pre Order cancelled successfully.': 'පූර්ව ඇණවුම සාර්ථකව අවලංගු කරන ලදී.',
    'Cancel Pre Order': 'පූර්ව ඇණවුම අවලංගු කරන්න',
    'Are you sure you want to cancel and delete this pre order? This cannot be undone.': 'ඔබට මෙම පූර්ව ඇණවුම අවලංගු කර මකා දැමීමට අවශ්‍ය බව විශ්වාසද?',
    'Keep': 'තබා ගන්න',
    'PRE-ORDER BILL / ESTIMATE': 'පූර්ව ඇණවුම් බිල්පත / තක්සේරුව',
    'Estimate No:': 'තක්සේරු අංකය:',
    'Due Date:': 'නියමිත දිනය:',
    'Customer:': 'පාරිභෝගිකයා:',
    'Phone:': 'දුරකථනය:',
    'Status:': 'තත්ත්වය:',
    'Items:': 'ද්‍රව්‍ය:',
    'Subtotal:': 'උප එකතුව:',
    'Discount:': 'වට්ටම්:',
    'Total Payable:': 'ගෙවිය යුතු මුළු මුදල:',
    'Advance Paid:': 'ලබා දුන් අත්පිට මුදල:',
    'Balance Settled:': 'පියවූ ශේෂය:',
    'Remaining Balance:': 'ඉතිරි ශේෂය:',
    'Balance Due:': 'ගෙවිය යුතු ශේෂය:',
    'Please present this estimate at checkout.': 'කරුණාකර ගෙවීමේදී මෙම තක්සේරු පත්‍රිකාව ඉදිරිපත් කරන්න.',
    'Print Estimate': 'තක්සේරුව මුද්‍රණය කරන්න',

    // POS Orders Screen
    'Search by Order ID, customer...': 'ඇණවුම් අංකය හෝ පාරිභෝගිකයාගෙන් සොයන්න...',
    'No orders found.': 'ඇණවුම් හමු නොවීය.',
    'ORDER ID': 'ඇණවුම් අංකය',
    'ORDER TYPE': 'ඇණවුම් වර්ගය',
    'CUSTOMER': 'පාරිභෝගිකයා',
    'AMOUNT': 'මුදල',
    'DATE': 'දිනය',
    'STATUS': 'තත්ත්වය',
    'ACTION': 'ක්‍රියාමාර්ගය',
    'Dining Table': 'ආහාර මේසය',
    'Takeaway': 'රැගෙන යාම',
    'Delivery': 'බෙදාහැරීම',
    'All': 'සියල්ල',
    'Showing 0 to 0 of 0 entries': 'ප්‍රවේශ 0 න් 0 ක් පෙන්වයි',
    'Try Again': 'නැවත උත්සාහ කරන්න',

    // Order Statuses
    'Pending': 'අපේක්ෂිත',
    'Accept': 'පිළිගන්න',
    'Preparing': 'සූදානම් කරමින්',
    'Prepared': 'සූදානම්',
    'Out For Delivery': 'බෙදාහැරීමට රැගෙන ගොස්',
    'Delivered': 'භාර දෙන ලදී',
    'Canceled': 'අවලංගුයි',
    'Cancelled': 'අවලංගුයි',
    'Returned': 'නැවත එවන ලදී',
    'Rejected': 'ප්‍රතික්ෂේපිත',

    // Dashboard & Stats
    'Total Sales': 'මුළු විකුණුම්',
    'Total Orders': 'මුළු ඇණවුම්',
    'Total Customers': 'මුළු පාරිභෝගිකයින්',
    'Total Menu Items': 'මුළු මෙනු ද්‍රව්‍ය',
    'Order Statistics': 'ඇණවුම් සංඛ්‍යාලේඛන',
    'Sales Summary': 'විකුණුම් සාරාංශය',
    'Orders Summary': 'ඇණවුම් සාරාංශය',

    // General Buttons & Actions
    'Search': 'සොයන්න',
    'Clear': 'පැහැදිලි කරන්න',
    'Filter': 'පෙරහන්',
    'Export': 'අපනයනය',
    'Add': 'එක් කරන්න',
    'Edit': 'සංස්කරණය',
    'Delete': 'මකන්න',
    'Save': 'සුරකින්න',
    'Close': 'වසා දමන්න',
    'Cancel': 'අවලංගු කරන්න',
    'Refresh': 'යාවත්කාලීන කරන්න',
    'Add Administrator': 'පරිපාලකයෙකු එක් කරන්න',
    'Add Customer': 'පාරිභෝගිකයෙකු එක් කරන්න',
    'Add Employee': 'සේවකයෙකු එක් කරන්න',
    'Add Waiter': 'වේටර්වරයෙකු එක් කරන්න',
    'Add Chef': 'සුපවේදියෙකු එක් කරන්න',
    'Add Delivery Boy': 'බෙදාහරින්නෙකු එක් කරන්න',
    'Search by name, email, or phone...': 'නම, ඊමේල් හෝ දුරකථනයෙන් සොයන්න...',
    'Reminder!': 'මතක් කිරීමක්!',
    'Dummy data will be reset in every 60 minutes.': 'සෑම විනාඩි 60 කට වරක් දත්ත යළි පිහිටුවනු ලැබේ.',
    'Version :': 'අනුවාදය : ',
  };

  static String translate(BuildContext context, String text) {
    try {
      final lang = Provider.of<DashboardController>(context, listen: true).selectedLanguage;
      if (lang == 'Sinhala') {
        return _sinhala[text] ?? text;
      }
    } catch (_) {}
    return text;
  }
}

extension TranslatableString on String {
  String tr(BuildContext context) => TranslationService.translate(context, this);
}
