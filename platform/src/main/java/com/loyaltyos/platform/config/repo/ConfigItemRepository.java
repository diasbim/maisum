package com.loyaltyos.platform.config.repo;

import com.loyaltyos.platform.config.domain.ConfigItem;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ConfigItemRepository extends JpaRepository<ConfigItem, UUID> {
  Optional<ConfigItem> findByKey(String key);
}
