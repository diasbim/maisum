import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/features/catalog/data/merchant_catalog_dao.dart';
import 'package:maisum/features/catalog/data/merchant_catalog_repository.dart';
import 'package:maisum/features/catalog/domain/merchant_item.dart';
import 'package:maisum/features/customers/data/customer_dao.dart';
import 'package:maisum/features/sales/data/sale_dao.dart';
import 'package:maisum/features/sales/data/sale_item_dao.dart';
import 'package:maisum/features/sales/data/sale_repository.dart';
import 'package:maisum/features/sales/domain/sale_item.dart';
import 'package:maisum/features/sync/data/sync_dao.dart';

import '../../helpers/test_database.dart';

void main() {
  const merchantId = 'merchant-1';
  const deviceId = 'device-1';

  late MerchantCatalogRepository catalogRepository;
  late MerchantCatalogDao catalogDao;
  late SyncDao syncDao;

  setUp(() async {
    await setUpTestDatabase();
    catalogDao =
        MerchantCatalogDao(AppDatabase.instance, merchantId: merchantId);
    syncDao = SyncDao(
      AppDatabase.instance,
      merchantId: merchantId,
      deviceId: deviceId,
    );
    catalogRepository = MerchantCatalogRepository(catalogDao, syncDao);
  });

  tearDown(tearDownTestDatabase);

  test('creates service and product catalog items', () async {
    final service = await catalogRepository.save(
      name: 'Haircut',
      type: MerchantItemType.service,
      defaultPrice: 500,
    );
    final product = await catalogRepository.save(
      name: 'Pomade',
      type: MerchantItemType.product,
    );

    expect((await catalogRepository.getServices()).single.id, service.id);
    expect((await catalogRepository.getProducts()).single.id, product.id);
    expect(await syncDao.getPendingCount(), 2);
  });

  test('updates and disables catalog item', () async {
    final item = await catalogRepository.save(
      name: 'Beard',
      type: MerchantItemType.service,
    );

    final updated = await catalogRepository.update(
      item.id,
      name: 'Premium Beard',
      defaultPrice: 250,
      isActive: false,
    );

    expect(updated!.name, 'Premium Beard');
    expect(updated.defaultPrice, 250);
    expect(updated.isActive, isFalse);
    expect(await catalogRepository.getActiveItems(), isEmpty);
  });

  test('delete fails once item is used by a sale item snapshot', () async {
    final customer = await CustomerDao(
      AppDatabase.instance,
      merchantId: merchantId,
    ).create(name: 'Ana', phone: '840000101');
    final item = await catalogRepository.save(
      name: 'Haircut',
      type: MerchantItemType.service,
      defaultPrice: 500,
    );
    final saleRepository = SaleRepository(
      AppDatabase.instance,
      SaleDao(AppDatabase.instance, merchantId: merchantId),
      merchantId: merchantId,
      deviceId: deviceId,
      saleItemDao: SaleItemDao(AppDatabase.instance, merchantId: merchantId),
    );

    await saleRepository.createSale(
      customerId: customer.id,
      amount: 500,
      items: [SaleItemInput.fromMerchantItem(item)],
    );

    expect(await catalogRepository.delete(item.id), isFalse);
  });
}
