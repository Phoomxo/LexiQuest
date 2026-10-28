import 'package:flutter/material.dart';
import '../models/user_rank.dart';
import '../services/rank_service.dart';
import '../widgets/accent_selector_widget.dart';

class ProfileSettingsScreen extends StatefulWidget {
  final String userName;
  final int totalXp;
  final int totalCoins;
  final RankService? rankService;

  const ProfileSettingsScreen({
    super.key,
    this.userName = 'คุณเพชร (Khun Phet)',
    this.totalXp = 1800,
    this.totalCoins = 350,
    this.rankService,
  });

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  late final RankService _rankService;
  late UserRank _userRank;
  VoiceAccent _selectedAccent = VoiceAccent.us;
  double _speechSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    _rankService = widget.rankService ?? const RankService();
    _userRank = _rankService.calculateRank(widget.totalXp);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'โปรไฟล์และการตั้งค่า (Profile & Settings)',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.indigo.shade800,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Profile Card
            Card(
              elevation: 4,
              color: Colors.indigo.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: Colors.indigo,
                      child: Text(
                        widget.userName.substring(0, 2),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.userName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade700,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'ยศ: ${_userRank.tier.nameEn} (${_userRank.tier.nameTh})',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'สะสม: ${widget.totalXp} XP | ${widget.totalCoins} เหรียญ',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Settings Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '⚙️ ตั้งค่าเสียง AI OmniVoice',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AccentSelectorWidget(
                      selectedAccent: _selectedAccent,
                      onAccentChanged: (accent) {
                        setState(() {
                          _selectedAccent = accent;
                        });
                      },
                    ),
                    const Divider(height: 30),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('ความเร็วเสียงอ่านเริ่มต้น:'),
                        Text(
                          '${_speechSpeed.toStringAsFixed(2)}x',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _speechSpeed,
                      min: 0.5,
                      max: 1.5,
                      divisions: 4,
                      activeColor: Colors.indigo,
                      onChanged: (val) {
                        setState(() {
                          _speechSpeed = val;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
