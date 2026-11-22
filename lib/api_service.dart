import 'dart:convert';
import 'package:dio/dio.dart';

class VoiceApi {
  static const String base = 'https://rahul99934-voice-detector.hf.space';
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 240),
    sendTimeout: const Duration(seconds: 120),
    headers: {'Accept': 'application/json'},
  ));

  Future<Map<String, dynamic>> predict(String filePath) async {
    try {
      final form = FormData.fromMap({
        'files': await MultipartFile.fromFile(filePath),
      });
      final upload = await _dio.post('$base/gradio_api/upload', data: form);
      if (upload.data is! List || (upload.data as List).isEmpty) {
        throw Exception('Audio upload failed: ${upload.data}');
      }
      final serverPath = (upload.data as List).first.toString();
      final response = await _dio.post('$base/gradio_api/call/predict', data: {
        'data': [
          {'path': serverPath, 'meta': {'_type': 'gradio.FileData'}}
        ],
      });
      final eventId = response.data?['event_id']?.toString();
      if (eventId == null || eventId.isEmpty) {
        throw Exception('No event_id returned. Check the Gradio API endpoint.');
      }
      final result = await _dio.get<String>(
        '$base/gradio_api/call/predict/$eventId',
        options: Options(responseType: ResponseType.plain),
      );
      String? event;
      for (final line in const LineSplitter().convert(result.data ?? '')) {
        if (line.startsWith('event:')) {
          event = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          final data = line.substring(5).trim();
          if (event == 'error') throw Exception('Model error: $data');
          if (event == 'complete') {
            final decoded = jsonDecode(data);
            if (decoded is List && decoded.isNotEmpty) {
              final output = decoded.first;
              if (output is Map) return Map<String, dynamic>.from(output);
              return {'result': output};
            }
            return {'result': decoded};
          }
        }
      }
      throw Exception('No completed prediction event. Response: ${result.data}');
    } on DioException catch (e) {
      throw Exception('API request failed (${e.response?.statusCode ?? 'network'}): ${e.response?.data ?? e.message}');
    }
  }
}
