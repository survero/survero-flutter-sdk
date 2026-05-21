import 'package:flutter/material.dart';
import '../models/models.dart';
import '../utils/color_utils.dart';

class StarRatingModal extends StatefulWidget {
  final SurveyConfig config;

  const StarRatingModal({super.key, required this.config});

  @override
  State<StarRatingModal> createState() => _StarRatingModalState();
}

class _StarRatingModalState extends State<StarRatingModal> {
  int _selectedRating = 0;
  final _commentController = TextEditingController();
  bool _submitting = false;

  SurveyConfig get config => widget.config;
  Color get primaryColor => hexToColor(config.style.primaryColor);
  double get radius => config.style.borderRadius;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_selectedRating == 0) return;

    setState(() => _submitting = true);

    final response = SurveroResponse(
      rating: _selectedRating,
      comment: _commentController.text.trim().isEmpty
          ? null
          : _commentController.text.trim(),
    );

    Navigator.of(context).pop(response);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Title
              Text(
                config.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 20),

              // Stars
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(config.settings.maxStars, (index) {
                  final starIndex = index + 1;
                  final isSelected = starIndex <= _selectedRating;

                  return GestureDetector(
                    onTap: () => setState(() => _selectedRating = starIndex),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: AnimatedScale(
                        scale: isSelected ? 1.1 : 1.0,
                        duration: const Duration(milliseconds: 150),
                        child: Icon(
                          isSelected ? Icons.star_rounded : Icons.star_outline_rounded,
                          size: config.settings.maxStars <= 5 ? 44 : 32,
                          color: isSelected ? primaryColor : Colors.grey.shade300,
                        ),
                      ),
                    ),
                  );
                }),
              ),

              // Comment field
              if (config.settings.showComment) ...[
                const SizedBox(height: 20),
                TextField(
                  controller: _commentController,
                  maxLines: 3,
                  maxLength: 2000,
                  decoration: InputDecoration(
                    hintText: 'Tell us more... (optional)',
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        radius.clamp(0, 12),
                      ),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        radius.clamp(0, 12),
                      ),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        radius.clamp(0, 12),
                      ),
                      borderSide: BorderSide(color: primaryColor, width: 2),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                    counterText: '',
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Submit button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _selectedRating > 0 && !_submitting ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade200,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        radius.clamp(0, 12),
                      ),
                    ),
                    elevation: 0,
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Submit',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
