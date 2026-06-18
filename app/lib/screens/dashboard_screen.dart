import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/dashboard_controller.dart';
import '../widgets/dashboard/reminder_banner.dart';
import '../widgets/dashboard/greeting_header.dart';
import '../widgets/dashboard/overview_cards.dart';
import '../widgets/dashboard/order_statistics.dart';
import '../widgets/dashboard/sales_summary_chart.dart';
import '../widgets/dashboard/orders_summary_radial.dart';
import '../widgets/dashboard/customer_stats_chart.dart';
import '../widgets/dashboard/top_customers_list.dart';
import '../widgets/dashboard/featured_items_grid.dart';
import '../widgets/dashboard/popular_items_list.dart';
import '../theme.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<DashboardController>(context, listen: false).loadDashboardData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<DashboardController>(context);
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 950;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: controller.isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              onRefresh: () => controller.loadDashboardData(),
              color: AppTheme.primary,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ReminderBanner(),
                    const SizedBox(height: 24),
                    const GreetingHeader(),
                    const SizedBox(height: 24),
                    OverviewCards(summary: controller.reportData?['summary']),
                    const SizedBox(height: 24),
                    OrderStatistics(
                      statuses: controller.reportData?['statuses'],
                      totalOrders: controller.reportData?['summary']?['total_orders']?.toInt() ?? 0,
                      dateRange: controller.statsDateRange,
                      onDateRangeChanged: controller.setStatsDateRange,
                    ),
                    const SizedBox(height: 24),

                    // Sales Summary & Orders Summary
                    if (isDesktop)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: SalesSummaryChart(
                              hourlySales: controller.reportData?['hourly_sales'],
                              totalSales: controller.reportData?['summary']?['total_sales']?.toDouble() ?? 0.0,
                              dateRange: controller.salesDateRange,
                              onDateRangeChanged: controller.setSalesDateRange,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: OrdersSummaryRadial(
                              statuses: controller.reportData?['statuses'],
                              dateRange: controller.ordersDateRange,
                              onDateRangeChanged: controller.setOrdersDateRange,
                            ),
                          ),
                        ],
                      )
                    else
                      Column(
                        children: [
                          SalesSummaryChart(
                            hourlySales: controller.reportData?['hourly_sales'],
                            totalSales: controller.reportData?['summary']?['total_sales']?.toDouble() ?? 0.0,
                            dateRange: controller.salesDateRange,
                            onDateRangeChanged: controller.setSalesDateRange,
                          ),
                          const SizedBox(height: 16),
                          OrdersSummaryRadial(
                            statuses: controller.reportData?['statuses'],
                            dateRange: controller.ordersDateRange,
                            onDateRangeChanged: controller.setOrdersDateRange,
                          ),
                        ],
                      ),
                    const SizedBox(height: 24),

                    // Customer Stats & Top Customers
                    if (isDesktop)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: CustomerStatsChart(
                              dateRange: controller.customerDateRange,
                              onDateRangeChanged: controller.setCustomerDateRange,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            flex: 2,
                            child: TopCustomersList(),
                          ),
                        ],
                      )
                    else
                      Column(
                        children: [
                          CustomerStatsChart(
                            dateRange: controller.customerDateRange,
                            onDateRangeChanged: controller.setCustomerDateRange,
                          ),
                          const SizedBox(height: 16),
                          const TopCustomersList(),
                        ],
                      ),
                    const SizedBox(height: 24),

                    // Featured Items & Most Popular Items
                    if (isDesktop)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Expanded(
                            flex: 3,
                            child: FeaturedItemsGrid(),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            flex: 2,
                            child: PopularItemsList(),
                          ),
                        ],
                      )
                    else
                      Column(
                        children: [
                          const FeaturedItemsGrid(),
                          const SizedBox(height: 16),
                          const PopularItemsList(),
                        ],
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
