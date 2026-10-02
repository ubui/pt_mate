import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/widgets/responsive_layout.dart';

void main() {
  void setPhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget buildRoot(WidgetTester tester) {
    return MaterialApp(
      home: ResponsiveLayout(
        currentRoute: '/',
        appBar: AppBar(title: const Text('首页')),
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ResponsiveLayout(
                    currentRoute: '/settings',
                    appBar: AppBar(title: const Text('设置')),
                    body: const SizedBox.shrink(),
                  ),
                ),
              ),
              child: const Text('push'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('根路由保留抽屉入口', (tester) async {
    setPhoneViewport(tester);
    await tester.pumpWidget(buildRoot(tester));
    await tester.pumpAndSettle();

    expect(find.byType(DrawerController), findsOneWidget);
    expect(find.byType(DrawerButton), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('子页面移除抽屉并显示返回按钮，返回后恢复', (tester) async {
    setPhoneViewport(tester);
    await tester.pumpWidget(buildRoot(tester));

    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    expect(find.byType(DrawerController), findsNothing);
    expect(find.byType(DrawerButton), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(DrawerController), findsOneWidget);
    expect(find.byType(DrawerButton), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
  });
}
