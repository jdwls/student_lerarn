import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:student/services/update_service.dart';

/// 学生端单元测试
///
/// 测试范围：
/// 1. 评分逻辑（选择题/连线题/顺序题/打字题/操作题）
/// 2. 登录验证逻辑
/// 3. 离线队列（失败重试、队列消费）
void main() {
  group('评分逻辑测试', () {
    // 提取自 scoring_utils.dart 的 `_isAnswerCorrect` 判定逻辑
    bool isAnswerCorrect(Map<String, dynamic> question, dynamic answer) {
      switch (question['type']) {
        case 'choice':
          return answer == question['answer'];
        case 'matching':
          final rawCorrect = question['correctMapping'];
          final correctMapping = <String, String>{};
          if (rawCorrect is Map) {
            rawCorrect.forEach((key, value) {
              correctMapping[key.toString()] = value.toString();
            });
          }
          final userMapping = <String, String>{};
          if (answer is Map) {
            final hasStableMapping = answer['mapping'] is Map;
            final rawMapping =
                hasStableMapping ? answer['mapping'] as Map : answer;
            final items = question['items'] as List<dynamic>? ?? [];
            rawMapping.forEach((key, value) {
              if (hasStableMapping) {
                userMapping[key.toString()] = value.toString();
                return;
              }
              final leftIndex = int.tryParse(key.toString());
              final rightIndex = int.tryParse(value.toString());
              if (leftIndex != null &&
                  rightIndex != null &&
                  leftIndex >= 0 &&
                  leftIndex < items.length &&
                  rightIndex >= 0 &&
                  rightIndex < items.length) {
                final leftId =
                    items[leftIndex]['leftId']?.toString() ?? '$leftIndex';
                final rightId =
                    items[rightIndex]['rightId']?.toString() ?? '$rightIndex';
                userMapping[leftId] = rightId;
              }
            });
          }
          if (correctMapping.length != userMapping.length) return false;
          for (final entry in correctMapping.entries) {
            if (userMapping[entry.key] != entry.value) return false;
          }
          return true;
        case 'sequential':
          final correct = (question['answer'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList();
          final userAnswer =
              (answer as List<dynamic>? ?? []).map((e) => e.toString()).toList();
          if (correct.length != userAnswer.length) return false;
          for (int i = 0; i < correct.length; i++) {
            if (correct[i] != userAnswer[i]) return false;
          }
          return true;
        case 'typing':
          return (answer is Map) && answer.containsKey('score');
        case 'operation':
          return answer is Map &&
              (answer['score'] is int
                  ? answer['score'] as int
                  : int.tryParse(answer['score']?.toString() ?? '0') ?? 0) > 0;
        default:
          return false;
      }
    }

    // 提取自 scoring_utils.dart 的 `_calculateScore` 计算逻辑
    ({
      int totalScore,
      int correctCount,
      List<Map<String, dynamic>> wrongQuestions,
    }) calculateScore(
      List<Map<String, dynamic>> questions,
      Map<int, dynamic> answers,
    ) {
      int totalScore = 0;
      int correctCount = 0;
      final wrongQuestions = <Map<String, dynamic>>[];

      for (int i = 0; i < questions.length; i++) {
        final question = questions[i];
        final answer = answers[i];
        final questionScore = question['score'] as int? ?? 0;
        final type = question['type'] as String? ?? '';

        if (type == 'operation') {
          final operationScore =
              (answer is Map ? answer['score'] : null) as int? ?? 0;
          totalScore += operationScore;
          if (operationScore > 0) {
            correctCount++;
          }
        } else if (answer != null) {
          final isCorrect = isAnswerCorrect(question, answer);
          if (isCorrect) {
            totalScore += questionScore;
            correctCount++;
          } else {
            wrongQuestions.add({
              'index': i,
              'number': question['number'] ?? '${i + 1}',
              'type': type,
              'correctAnswer': question['answer'],
              'userAnswer': answer,
            });
          }
        }
      }
      return (
        totalScore: totalScore,
        correctCount: correctCount,
        wrongQuestions: wrongQuestions,
      );
    }

    group('选择题评分', () {
      test('答对得满分', () {
        final question = {
          'type': 'choice',
          'number': '1',
          'score': 5,
          'answer': 'A',
        };
        expect(isAnswerCorrect(question, 'A'), isTrue);
        final result = calculateScore([question], {0: 'A'});
        expect(result.totalScore, 5);
        expect(result.correctCount, 1);
        expect(result.wrongQuestions, isEmpty);
      });

      test('答错不得分', () {
        final question = {
          'type': 'choice',
          'number': '1',
          'score': 5,
          'answer': 'A',
        };
        expect(isAnswerCorrect(question, 'B'), isFalse);
        final result = calculateScore([question], {0: 'B'});
        expect(result.totalScore, 0);
        expect(result.correctCount, 0);
        expect(result.wrongQuestions, hasLength(1));
      });

      test('未作答不计分不算错', () {
        final question = {
          'type': 'choice',
          'number': '1',
          'score': 5,
          'answer': 'A',
        };
        final result = calculateScore([question], {});
        expect(result.totalScore, 0);
        expect(result.correctCount, 0);
        expect(result.wrongQuestions, isEmpty);
      });
    });

    group('连线题评分', () {
      final question = {
        'type': 'matching',
        'number': '2',
        'score': 10,
        'items': [
          {'leftId': 'a', 'rightId': '1'},
          {'leftId': 'b', 'rightId': '2'},
        ],
        'correctMapping': {'a': '1', 'b': '2'},
      };

      test('连线全部正确', () {
        final answer = {'0': '0', '1': '1'}; // 左索引->右索引
        expect(isAnswerCorrect(question, answer), isTrue);
        final result = calculateScore([question], {0: answer});
        expect(result.totalScore, 10);
        expect(result.correctCount, 1);
      });

      test('连线部分错误', () {
        final answer = {'0': '1', '1': '0'}; // 交叉连线
        expect(isAnswerCorrect(question, answer), isFalse);
        final result = calculateScore([question], {0: answer});
        expect(result.totalScore, 0);
        expect(result.wrongQuestions, hasLength(1));
      });

      test('稳定mapping格式答案', () {
        final answer = {
          'mapping': {'a': '1', 'b': '2'}
        };
        expect(isAnswerCorrect(question, answer), isTrue);
      });

      test('连线数量不匹配', () {
        final answer = {'0': '0'}; // 只连一条
        expect(isAnswerCorrect(question, answer), isFalse);
      });
    });

    group('顺序题评分', () {
      final question = {
        'type': 'sequential',
        'number': '3',
        'score': 6,
        'answer': ['1', '2', '3'],
      };

      test('顺序完全正确', () {
        final answer = ['1', '2', '3'];
        expect(isAnswerCorrect(question, answer), isTrue);
        final result = calculateScore([question], {0: answer});
        expect(result.totalScore, 6);
        expect(result.correctCount, 1);
      });

      test('顺序错误', () {
        final answer = ['3', '2', '1'];
        expect(isAnswerCorrect(question, answer), isFalse);
        final result = calculateScore([question], {0: answer});
        expect(result.totalScore, 0);
        expect(result.wrongQuestions, hasLength(1));
      });

      test('数量不一致', () {
        final answer = ['1', '2'];
        expect(isAnswerCorrect(question, answer), isFalse);
      });
    });

    group('打字题评分', () {
      test('有score字段即视为正确', () {
        final question = {'type': 'typing', 'number': '4', 'score': 10};
        expect(isAnswerCorrect(question, {'score': 8}), isTrue);
        final result = calculateScore([question], {0: {'score': 8}});
        expect(result.totalScore, 10);
        expect(result.correctCount, 1);
      });

      test('无score字段视为未完成', () {
        final question = {'type': 'typing', 'number': '4', 'score': 10};
        expect(isAnswerCorrect(question, {}), isFalse);
      });
    });

    group('操作题评分', () {
      test('得分大于0视为正确', () {
        final question = {'type': 'operation', 'number': '5', 'score': 20};
        expect(isAnswerCorrect(question, {'score': 15, 'completed': true}), isTrue);
        final result = calculateScore([question], {0: {'score': 15, 'completed': true}});
        expect(result.totalScore, 15); // 操作题使用实际批改得分
        expect(result.correctCount, 1);
      });

      test('得分为0视为错误', () {
        final question = {'type': 'operation', 'number': '5', 'score': 20};
        expect(isAnswerCorrect(question, {'score': 0, 'completed': true}), isFalse);
      });

      test('未作答计0分', () {
        final question = {'type': 'operation', 'number': '5', 'score': 20};
        final result = calculateScore([question], {});
        expect(result.totalScore, 0);
      });

      test('操作题得分为部分分', () {
        final question = {'type': 'operation', 'number': '5', 'score': 20};
        final result = calculateScore([question], {0: {'score': 7, 'completed': true}});
        expect(result.totalScore, 7);
      });
    });

    group('混合题型总分计算', () {
      test('多题型综合计分', () {
        final questions = [
          {'type': 'choice', 'number': '1', 'score': 5, 'answer': 'A'},
          {'type': 'matching', 'number': '2', 'score': 10, 'items': [
            {'leftId': 'a', 'rightId': '1'},
            {'leftId': 'b', 'rightId': '2'},
          ], 'correctMapping': {'a': '1', 'b': '2'}},
          {'type': 'sequential', 'number': '3', 'score': 6, 'answer': ['1', '2', '3']},
          {'type': 'operation', 'number': '5', 'score': 20},
          {'type': 'choice', 'number': '6', 'score': 5, 'answer': 'B'},
        ];

        final answers = {
          0: 'A', // 对，+5
          1: {'0': '0', '1': '1'}, // 对，+10
          2: ['3', '2', '1'], // 错，+0
          3: {'score': 12, 'completed': true}, // 操作题部分分，+12
          4: 'C', // 错，+0
        };

        final result = calculateScore(questions, answers);
        expect(result.totalScore, 5 + 10 + 12); // 27
        expect(result.correctCount, 3); // 选择1 + 连线1 + 操作1
        expect(result.wrongQuestions, hasLength(2)); // 顺序1 + 选择2
      });

      test('所有题未作答得0分', () {
        final questions = [
          {'type': 'choice', 'number': '1', 'score': 5, 'answer': 'A'},
          {'type': 'choice', 'number': '2', 'score': 5, 'answer': 'B'},
        ];
        final result = calculateScore(questions, {});
        expect(result.totalScore, 0);
        expect(result.correctCount, 0);
        expect(result.wrongQuestions, isEmpty);
      });
    });

    group('最大分计算', () {
      test('计算所有题目分值之和', () {
        final questions = [
          {'type': 'choice', 'number': '1', 'score': 5},
          {'type': 'choice', 'number': '2', 'score': 10},
          {'type': 'operation', 'number': '3', 'score': 20},
        ];
        int calculateMaxScore() {
          var max = 0;
          for (final question in questions) {
            max += question['score'] as int? ?? 0;
          }
          return max;
        }

        expect(calculateMaxScore(), 35);
      });
    });
  });

  group('登录验证测试', () {
    test('登录参数不能为空', () {
      bool validateLogin(String? name, String? password) {
        return (name?.isNotEmpty ?? false) && (password?.isNotEmpty ?? false);
      }

      expect(validateLogin('', ''), false);
      expect(validateLogin(null, null), false);
      expect(validateLogin('张三', ''), false);
      expect(validateLogin('', '123'), false);
      expect(validateLogin('张三', '123'), true);
    });

    test('密码长度校验', () {
      bool isValidPassword(String password) {
        return password.length >= 1 && password.length <= 20;
      }

      expect(isValidPassword('1'), true);
      expect(isValidPassword('123456'), true);
      expect(isValidPassword('a' * 20), true);
      expect(isValidPassword(''), false);
      expect(isValidPassword('a' * 21), false);
    });

    test('设备信息自动登录匹配', () {
      // 自动登录：电脑名+IP 匹配
      bool autoLoginMatch(String savedComputer, String savedIp,
          String currentComputer, String currentIp) {
        return savedComputer == currentComputer && savedIp == currentIp;
      }

      expect(autoLoginMatch('PC-01', '192.168.1.10', 'PC-01', '192.168.1.10'), true);
      expect(autoLoginMatch('PC-01', '192.168.1.10', 'PC-02', '192.168.1.10'), false);
      expect(autoLoginMatch('PC-01', '192.168.1.10', 'PC-01', '192.168.1.11'), false);
    });
  });

  group('离线成绩队列测试', () {
    test('提交失败时入队保存', () {
      // 模拟 savePendingSubmission 逻辑
      final queue = <Map<String, dynamic>>[];

      void savePendingSubmission({
        required String studentId,
        required String studentName,
        required String bankName,
        required String classId,
        required int score,
        required Map<String, dynamic> answers,
      }) {
        queue.add({
          'studentId': studentId,
          'studentName': studentName,
          'bankName': bankName,
          'classId': classId,
          'score': score,
          'answers': answers,
          'timestamp': DateTime.now().toIso8601String(),
        });
      }

      savePendingSubmission(
        studentId: 'stu_001',
        studentName: '张三',
        bankName: '测试题库',
        classId: '初一01班',
        score: 85,
        answers: {'1': {'answer': 'A'}},
      );

      expect(queue, hasLength(1));
      expect(queue.first['score'], 85);
      expect(queue.first['studentId'], 'stu_001');
    });

    test('队列消费成功时移除记录', () {
      // 模拟 drainPendingTypingSubmissions：成功则移除，失败则保留并重试
      final queue = [
        {
          'studentId': 'stu_001',
          'score': 85,
          'retry_count': 0,
        },
        {
          'studentId': 'stu_002',
          'score': 90,
          'retry_count': 0,
        },
      ];

      Future<bool> submitToServer(Map<String, dynamic> entry) async {
        // 假设 stu_002 失败
        return entry['studentId'] != 'stu_002';
      }

      Future<List<Map<String, dynamic>>> drain(List<Map<String, dynamic>> raw) async {
        final remaining = <Map<String, dynamic>>[];
        for (final entry in raw) {
          try {
            final success = await submitToServer(entry);
            if (success) continue;
          } catch (_) {}
          entry['retry_count'] = (entry['retry_count'] as int) + 1;
          remaining.add(entry);
        }
        return remaining;
      }

      final remaining = drain(queue) as Future<List<Map<String, dynamic>>>;

      // 使用 async 测试
      // ignore: discarded_futures
      expect(remaining, completion(hasLength(1)));
    });
  });

  group('本地存储原子写入测试', () {
    test('JSON序列化与反序列化格式正确', () {
      final data = {
        'student_id': 'stu_001',
        'score': 85,
        'questions_detail': [
          {'index': 0, 'type': '选择题', 'score': 5, 'earnedScore': 5},
        ],
      };

      final jsonString = json.encode(data);
      final decoded = json.decode(jsonString) as Map<String, dynamic>;

      expect(decoded['student_id'], 'stu_001');
      expect(decoded['score'], 85);
      expect((decoded['questions_detail'] as List), hasLength(1));
    });

    test('Base64题库内容编码与解码', () {
      final data = {
        'choiceQuestions': [
          {'题干': '测试', '答案': 'A'},
        ],
      };

      final jsonString = json.encode(data);
      final encoded = base64Encode(utf8.encode(jsonString));

      final decodedJson = utf8.decode(base64Decode(encoded));
      final decoded = json.decode(decodedJson) as Map<String, dynamic>;

      expect(decoded, data);
      expect((decoded['choiceQuestions'] as List).first['题干'], '测试');
    });

    test('损坏的JSON文件返回空Map', () {
      Map<String, dynamic> readJsonSafe(String content) {
        try {
          return json.decode(content) as Map<String, dynamic>;
        } catch (_) {
          return {};
        }
      }

      expect(readJsonSafe('{invalid json'), isEmpty);
      expect(readJsonSafe(''), isEmpty);
      expect(readJsonSafe('{"valid": true}'), {'valid': true});
    });
  });

  group('在线升级 - 版本比较', () {
    test('语义化版本比较', () {
      expect(UpdateService.compareVersions('1.1.0', '1.0.0'), 1);
      expect(UpdateService.compareVersions('1.0.0', '1.1.0'), -1);
      expect(UpdateService.compareVersions('1.0.0', '1.0.0'), 0);
      expect(UpdateService.compareVersions('1.0', '1.0.0'), 0);
      expect(UpdateService.compareVersions('2.0', '1.9.9'), 1);
      expect(UpdateService.compareVersions('1.0.0', '1.0.10'), -1);
    });
  });

  group('在线升级 - 安装包 MD5', () {
    test('computeFileMd5 与标准向量一致（分块读取）', () async {
      final dir = await Directory.systemTemp.createTemp('md5_check_');
      try {
        final file = File('${dir.path}${Platform.pathSeparator}a.txt');
        await file.writeAsString('abc');
        // MD5("abc")
        expect(await computeFileMd5(file.path),
            '900150983cd24fb0d6963f7d28e17f72');

        final emptyFile = File('${dir.path}${Platform.pathSeparator}b.txt');
        await emptyFile.writeAsString('');
        // MD5("")
        expect(await computeFileMd5(emptyFile.path),
            'd41d8cd98f00b204e9800998ecf8427e');
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('UpdateInfo 解析 file_size / md5 / force_update', () {
      // min_version 已随本次升级改造废除（强制升级统一走 force_update）
      final info = UpdateInfo.fromJson({
        'version': '1.1.0',
        'file_name': 'student.exe',
        'file_size': 123,
        'md5': 'ABC123',
        'force_update': true,
        'min_version': '1.0.5', // 旧字段应被忽略，不再映射
      });
      expect(info.version, '1.1.0');
      expect(info.fileName, 'student.exe');
      expect(info.fileSize, 123);
      expect(info.md5Hex, 'ABC123');
      expect(info.forceUpdate, isTrue);
    });

    test('UpdateInfo 缺省字段安全降级', () {
      final info = UpdateInfo.fromJson({'version': '1.0.1'});
      expect(info.fileName, '');
      expect(info.fileSize, 0);
      expect(info.md5Hex, '');
      expect(info.forceUpdate, isFalse);
    });
  });
}