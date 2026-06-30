import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/dashboard_controller.dart';

class TranslationService {
  static const Map<String, String> _sinhala = {
    'Dashboard': 'පුවරුව',
    'Items': 'මෙනු ද්‍රව්‍ය',
    'Dining Tables': 'ආහාර මේස',
    'POS System': 'POS පද්ධතිය',
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
    'Good Morning!': 'සුභ උදෑසනක්!',
    'Total Sales': 'මුළු විකුණුම්',
    'Total Orders': 'මුළු ඇණවුම්',
    'Total Customers': 'මුළු පාරිභෝගිකයින්',
    'Total Menu Items': 'මුළු මෙනු ද්‍රව්‍ය',
    'Order Statistics': 'ඇණවුම් සංඛ්‍යාලේඛන',
    'Pending': 'ප්‍රතිචාර අපේක්ෂිත',
    'Accept': 'පිළිගන්න',
    'Preparing': 'සූදානම් කරමින්',
    'Prepared': 'සූදානම්',
    'Out For Delivery': 'බෙදාහැරීමට රැගෙන ගොස්',
    'Delivered': 'භාර දෙන ලදී',
    'Canceled': 'අවලංගු කරන ලදී',
    'Cancelled': 'අවලංගු කරන ලදී',
    'Returned': 'නැවත එවන ලදී',
    'Rejected': 'ප්‍රතික්ෂේප කරන ලදී',
    'Sales Summary': 'විකුණුම් සාරාංශය',
    'Orders Summary': 'ඇණවුම් සාරාංශය',
    'Online': 'සබැඳි',
    'Offline': 'නොබැඳි',
    'SHIFT OPEN': 'මුදල් මාරුව විවෘතයි',
    'Logout': 'පිටවීම',
    'Hello': 'ආයුබෝවන්',
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
    'Add Administrator': 'පරිපාලකයෙකු එක් කරන්න',
    'Add Customer': 'පාරිභෝගිකයෙකු එක් කරන්න',
    'Add Employee': 'සේවකයෙකු එක් කරන්න',
    'Add Waiter': 'වේටර්වරයෙකු එක් කරන්න',
    'Add Chef': 'සුපවේදියෙකු එක් කරන්න',
    'Add Delivery Boy': 'බෙදාහරින්නෙකු එක් කරන්න',
    'Refresh': 'යාවත්කාලීන කරන්න',
    'Search by name, email, or phone...': 'නම, ඊමේල් හෝ දුරකථනයෙන් සොයන්න...',
    'Reminder!': 'මතක් කිරීමක්!',
    'Dummy data will be reset in every 60 minutes.': 'සෑම විනාඩි 60 කට වරක් දත්ත යළි පිහිටුවනු ලැබේ.',
    'Version : 3.9': 'අනුවාදය : 3.9',
    'USERS': 'පරිශීලකයින්',
    'REPORTS & SHIFTS': 'වාර්තා සහ මාරුවීම්',
    'STOCKS': 'තොග',
    'SYSTEM': 'පද්ධතිය',
    'PROMO': 'ප්‍රවර්ධන',
    'POS & ORDERS': 'POS සහ ඇණවුම්',
    'Good Afternoon!': 'සුභ පස්වරුවක්!',
    'Good Evening!': 'සුභ සැන්දෑවක්!',
    'Guest User': 'අමුත්තා',
    'English': 'ඉංග්‍රීසි',
    'Sinhala': 'සිංහල',
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
