import 'package:flutter/material.dart';
import 'package:control_app/update_checker.dart';
import 'screen_project_selection.dart';
import 'screen_personnel.dart';
import 'screen_attendance_viewer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const ProjectSelectionScreen(),
    const PersonnelScreen(),
    const AttendanceViewerScreen(),
  ];

  @override
  void initState(){
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => UpdateChecker.check(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C1CF0),
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF0000FF),
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.grey,
        elevation: 8,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.construction),
            label: 'OBRAS',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'PERSONAL',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.checklist),
            label: 'ASISTENCIA',
          ),
        ],
      ),
    );
  }
}