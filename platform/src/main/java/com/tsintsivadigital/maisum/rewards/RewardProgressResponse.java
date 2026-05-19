package com.tsintsivadigital.maisum.rewards;

public class RewardProgressResponse {
  private final int currentPoints;
  private final String nextReward;
  private final int pointsRemaining;
  private final int progressPercentage;

  public RewardProgressResponse(
      int currentPoints,
      String nextReward,
      int pointsRemaining,
      int progressPercentage) {
    this.currentPoints = currentPoints;
    this.nextReward = nextReward;
    this.pointsRemaining = pointsRemaining;
    this.progressPercentage = progressPercentage;
  }

  public int getCurrentPoints() {
    return currentPoints;
  }

  public String getNextReward() {
    return nextReward;
  }

  public int getPointsRemaining() {
    return pointsRemaining;
  }

  public int getProgressPercentage() {
    return progressPercentage;
  }
}
