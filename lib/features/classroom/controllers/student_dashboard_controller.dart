import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/classroom_session.dart';
import '../models/classroom_assignment.dart';
import '../models/classroom_submission.dart';
import '../repositories/classroom_repository.dart';

class StudentDashboardController extends ChangeNotifier {
  final ClassroomRepository _repository;

  List<ClassroomSession> availableSessions = [];
  List<ClassroomAssignment> assignments = [];
  List<ClassroomSubmission> mySubmissions = [];

  StreamSubscription? _sessionsSub;
  StreamSubscription? _assignmentsSub;
  StreamSubscription? _submissionsSub;

  StudentDashboardController(this._repository) {
    _initStreams();
  }

  void _initStreams() async {
    availableSessions = await _repository.fetchActiveSessions();
    notifyListeners();

    _sessionsSub = _repository.sessionsStream.listen((sessions) {
      availableSessions = sessions.where((s) => s.isActive).toList();
      notifyListeners();
    });

    _assignmentsSub = _repository.assignmentsStream.listen((assigns) {
      assignments = assigns;
      notifyListeners();
    });

    _submissionsSub = _repository.submissionsStream.listen((subs) {
      // Filter for this student only
      mySubmissions = subs.where((s) => s.studentName == 'Local Student').toList();
      notifyListeners();
    });
  }

  Future<void> simulateRunAndSubmit(String assignmentId) async {
    final submission = ClassroomSubmission(
      id: const Uuid().v4(),
      assignmentId: assignmentId,
      studentName: 'Local Student',
      status: 'Completed',
      completionTime: DateTime.now(),
      submissionTime: DateTime.now(),
      resultMetrics: {'score': 100, 'timeSpentSeconds': 120},
    );
    await _repository.submitAssignment(submission);
  }

  bool isSubmitted(String assignmentId) {
    return mySubmissions.any((s) => s.assignmentId == assignmentId);
  }

  @override
  void dispose() {
    _sessionsSub?.cancel();
    _assignmentsSub?.cancel();
    _submissionsSub?.cancel();
    super.dispose();
  }
}
