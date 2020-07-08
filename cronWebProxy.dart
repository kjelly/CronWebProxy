import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:cron/cron.dart';
import 'package:hive/hive.dart';
import 'package:args/args.dart';

void updateBox(String base, List<String> pathList, Box header ,Box body){
    for (var i in pathList) {
      var url = [base, i].join('');
      http.get(url).then((response) async {
        print('corn job:' + i);
        body.put(i, response.body);
        header.put(i, response.headers);
      });
    }
}

void main(List<String> args) async {
  var parser = ArgParser();

  parser.addMultiOption('path', abbr: 'p', defaultsTo: ['/']);
  parser.addOption('cache', abbr: 'c', defaultsTo: '/tmp/cronWebProxy/');
  parser.addOption('port', defaultsTo: '4040');
  parser.addOption('base', abbr: 'b', defaultsTo: 'http://localhost/');
  parser.addOption('interval', abbr: 'i', defaultsTo: '* * * * *');


  var results = parser.parse(args);

  var base = results['base'];
  var pathList = results['path'];
  var port = int.tryParse(results['port']) ?? 4040;
  var cron = new Cron();

  Hive.init(results['cache']);
  var body = await Hive.openBox('body');
  var header = await Hive.openBox('header');

  var server = await HttpServer.bind(
    InternetAddress.ANY_IP_V4,
    port
  );

  updateBox(base, pathList, header, body);
  cron.schedule(new Schedule.parse(results['interval']), () async {
    updateBox(base, pathList, header, body);
  });

  print('Server start');
  await for (HttpRequest request in server) {
    print(request.uri);
    var path = request.uri.toString();
    var url = base + path;
    if(!pathList.contains(path)){
      pathList.add(path);
    }
    if (body.containsKey(path)) {
      (Map<String, String>.from(header.get(path))).forEach((key, value) {
        request.response.headers.set(key, value);
      });
      request.response.write(body.get(path).toString());
      await request.response.close();
      print('From box');
    } else {
      http.get(url).then((response) async {
        body.put(path, response.body);
        header.put(path, response.headers);

        response.headers.forEach((key, value) {
          request.response.headers.set(key, value);
        });

        request.response.write(response.body);
        await request.response.close();
      });
    }
  }
}
