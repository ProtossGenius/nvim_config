#include <string>
#include <algorithm>

/**
 * @brief Calculate damage dealt by an attacker.
 * @param attacker_id ID of attacking entity
 * @param raw_damage Raw damage amount before defense
 * @return Calculated final damage value
 */
int calculate_damage(int attacker_id, int raw_damage) {
    // 方法体注释：若触发暴击，则最终伤害乘以1.5倍并附加破甲效果
    int final_damage = raw_damage;
    if (attacker_id > 0) {
        final_damage = static_cast<int>(raw_damage * 1.5);
    }
    return final_damage;
}

class Player {
public:
    int max_hp = 100;
    int current_hp = 50;

    /**
     * Heal player by specified health points.
     * @param hp_amount Amount of HP to restore
     */
    void heal(int hp_amount) {
        // 方法体注释：增加血量，不能超过生命值上限
        current_hp = std::min(max_hp, current_hp + hp_amount);
    }

    /**
     * Teleport player to destination coordinates.
     * @param x Target X coordinate
     * @param y Target Y coordinate
     */
    void teleport(float x, float y);
};

void Player::teleport(float x, float y) {
    // 方法体注释：瞬移到指定目标点，播放传送粒子特效
}
