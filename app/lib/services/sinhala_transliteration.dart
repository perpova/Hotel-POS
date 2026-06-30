class SinhalaTransliteration {
  // Mapping of vowel sounds at the beginning of words
  static const Map<String, String> _vowels = {
    'aae': 'ඈ',
    'ae': 'ඇ',
    'aa': 'ආ',
    'a': 'අ',
    'ii': 'ඊ',
    'i': 'ඉ',
    'uu': 'ඌ',
    'u': 'උ',
    'ee': 'ඒ',
    'e': 'එ',
    'oo': 'ඕ',
    'o': 'ඔ',
    'au': 'ඖ',
  };

  // Mapping of consonants
  static const Map<String, String> _consonants = {
    'ndr': 'න්ද්‍ර',
    'nnd': 'ණ්ණ',
    'kkh': 'ක්ඛ',
    'ggh': 'ග්ඝ',
    'cch': 'ච්ඡ',
    'jjh': 'ජ්ඣ',
    'tth': 'ට්ඨ',
    'ddh': 'ඩ්ඪ',
    'pph': 'ප්ඵ',
    'bbh': 'බ්භ',
    'nd': 'ඳ',
    'ng': 'ඟ',
    'nj': 'ඤ',
    'mb': 'ඹ',
    'th': 'ත',
    'dh': 'ද',
    'ch': 'ච',
    'jh': 'ජ',
    'sh': 'ශ',
    'kh': 'ඛ',
    'gh': 'ඝ',
    'ph': 'ඵ',
    'bh': 'භ',
    'k': 'ක',
    'g': 'ග',
    'c': 'ච',
    'j': 'ජ',
    't': 'ට',
    'd': 'ඩ',
    'n': 'න',
    'p': 'ප',
    'b': 'බ',
    'm': 'ම',
    'y': 'ය',
    'r': 'ර',
    'l': 'ල',
    'v': 'ව',
    'w': 'ව',
    's': 'ස',
    'h': 'හ',
    'f': 'ෆ',
    'x': 'ක්ස්',
    'q': 'කූ',
  };

  // Vowel modifiers (pillas)
  static const Map<String, String> _vowelModifiers = {
    'aae': 'ෑ',
    'ae': 'ැ',
    'aa': 'ා',
    'a': '', // default vowel sound
    'ii': 'ී',
    'i': 'ි',
    'uu': 'ූ',
    'u': 'ු',
    'ee': 'ේ',
    'e': 'ෙ',
    'oo': 'ෝ',
    'o': 'ො',
    'au': 'ෞ',
  };

  static String transliterate(String input) {
    if (input.isEmpty) return '';

    final text = input.toLowerCase();
    final buffer = StringBuffer();
    int i = 0;

    while (i < text.length) {
      final char = text[i];

      // If it is not a letter, output directly
      if (!RegExp(r'[a-z]').hasMatch(char)) {
        buffer.write(input[i]);
        i++;
        continue;
      }

      // 1. Check if it's a word-start vowel sound
      bool isWordStart = (i == 0 || !RegExp(r'[a-z]').hasMatch(text[i - 1]));
      if (isWordStart) {
        String? matchedVowel;
        int vowelLen = 0;
        for (final key in _vowels.keys) {
          if (text.startsWith(key, i)) {
            matchedVowel = _vowels[key];
            vowelLen = key.length;
            break;
          }
        }
        if (matchedVowel != null) {
          buffer.write(matchedVowel);
          i += vowelLen;
          continue;
        }
      }

      // 2. Match the longest consonant prefix
      String? matchedConsonant;
      int consonantLen = 0;
      for (final key in _consonants.keys) {
        if (text.startsWith(key, i)) {
          matchedConsonant = _consonants[key];
          consonantLen = key.length;
          break;
        }
      }

      if (matchedConsonant != null) {
        int nextIdx = i + consonantLen;
        
        // Check if a vowel modifier follows the consonant
        String? matchedModifier;
        int modifierLen = 0;
        for (final key in _vowelModifiers.keys) {
          if (text.startsWith(key, nextIdx)) {
            matchedModifier = _vowelModifiers[key];
            modifierLen = key.length;
            break;
          }
        }

        if (matchedModifier != null) {
          buffer.write(matchedConsonant);
          buffer.write(matchedModifier);
          i = nextIdx + modifierLen;
        } else {
          // If no vowel follows, add hal-kirima (්) to mute the consonant vowel sound
          buffer.write(matchedConsonant);
          buffer.write('්');
          i = nextIdx;
        }
      } else {
        // Fallback for unmapped vowel character or solo letters
        buffer.write(input[i]);
        i++;
      }
    }

    return buffer.toString();
  }
}
