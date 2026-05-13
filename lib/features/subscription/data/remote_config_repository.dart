import '../domain/remote_config.dart';
import 'remote_config_dao.dart';

class RemoteConfigRepository {
  RemoteConfigRepository(this._dao);

  final RemoteConfigDao _dao;

  Future<RemoteConfigEntry?> getConfig(String configKey) {
    return _dao.getConfig(configKey);
  }

  Future<List<RemoteConfigEntry>> getAllConfigs() {
    return _dao.getAllConfigs();
  }
}
