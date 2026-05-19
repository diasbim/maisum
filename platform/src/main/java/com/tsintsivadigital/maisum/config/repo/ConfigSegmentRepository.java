package com.tsintsivadigital.maisum.config.repo;

import com.tsintsivadigital.maisum.config.domain.ConfigSegment;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ConfigSegmentRepository extends JpaRepository<ConfigSegment, UUID> {}
