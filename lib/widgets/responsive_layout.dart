import 'package:flutter/material.dart';
import 'app_drawer.dart';
import '../utils/screen_utils.dart';

class ResponsiveLayout extends StatelessWidget {
  final Widget body;
  final PreferredSizeWidget? appBar;
  final String? currentRoute;
  final VoidCallback? onSettingsChanged;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  const ResponsiveLayout({
    super.key,
    required this.body,
    this.appBar,
    this.currentRoute,
    this.onSettingsChanged,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 判断是否为大屏设备（宽度大于 768px）
        final isLargeScreen = ScreenUtils.isLargeScreen(context);
        // 子页面让出左边缘手势给系统返回，并由 AppBar 自动显示返回按钮
        final route = ModalRoute.of(context);
        final isPushed = route != null && !route.isFirst;

        if (isLargeScreen) {
          // 大屏设备：使用固定侧边栏布局
          return Scaffold(
            appBar: appBar != null ? _buildAppBarForLargeScreen(context) : null,
            floatingActionButton: floatingActionButton,
            floatingActionButtonLocation: floatingActionButtonLocation,
            body: SafeArea(
              top: true,
              bottom: true,
              child: Row(
                children: [
                  // 固定侧边栏
                  SizedBox(
                    width: 240,
                    child: AppDrawer(
                      currentRoute: currentRoute,
                      onSettingsChanged: onSettingsChanged,
                      isFixedSidebar: true,
                    ),
                  ),
                  // 主内容区域
                  Expanded(child: body),
                ],
              ),
            ),
          );
        } else {
          // 小屏设备：使用传统的 Drawer 布局
          // 子页面不挂抽屉，避免左边缘手势被抽屉抢占，同时让 AppBar 自动切换为返回按钮
          return Scaffold(
            appBar: appBar,
            drawer: isPushed
                ? null
                : AppDrawer(
                    currentRoute: currentRoute,
                    onSettingsChanged: onSettingsChanged,
                    isFixedSidebar: false,
                  ),
            floatingActionButton: floatingActionButton,
            floatingActionButtonLocation: floatingActionButtonLocation,
            body: SafeArea(top: true, bottom: true, child: body),
          );
        }
      },
    );
  }

  PreferredSizeWidget _buildAppBarForLargeScreen(BuildContext context) {
    if (appBar is AppBar) {
      final originalAppBar = appBar as AppBar;
      return AppBar(
        title: originalAppBar.title,
        actions: originalAppBar.actions,
        backgroundColor: originalAppBar.backgroundColor,
        iconTheme: originalAppBar.iconTheme,
        titleTextStyle: originalAppBar.titleTextStyle,
        // 大屏设备不需要菜单按钮，因为侧边栏是固定显示的
        automaticallyImplyLeading: false,
      );
    }
    return appBar!;
  }
}