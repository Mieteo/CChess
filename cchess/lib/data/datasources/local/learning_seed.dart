import '../../models/learning_lesson.dart';

const List<LearningLesson> beginnerLessons = [
  LearningLesson(
    id: 'b001',
    order: 1,
    titleVi: 'Làm quen bàn cờ',
    subtitleVi: 'Mục tiêu ván cờ, cung Tướng, sông và cách đọc tọa độ.',
    levelLabel: 'Nhập môn',
    estimatedMinutes: 5,
    focusPieces: ['Bàn cờ', 'Tướng'],
    sections: [
      LessonSection(
        title: 'Mục tiêu của ván cờ',
        body:
            'Cờ Tướng xoay quanh việc bảo vệ Tướng của mình và tạo thế chiếu bí Tướng đối phương. Người mới nên học cách nhìn đường quân trước khi học khai cuộc.',
        bullets: [
          'Bàn cờ có 10 hàng, 9 cột và một dòng sông ở giữa.',
          'Mỗi bên có một cung Tướng rộng 3 x 3 ở cuối bàn.',
          'Một nước đi tốt luôn vừa tạo lợi thế vừa không để Tướng bị nguy hiểm.',
        ],
      ),
      LessonSection(
        title: 'Đọc thế cờ chậm lại',
        body:
            'Trước khi chạm quân, hãy nhìn ba thứ: Tướng hai bên, quân đang bị tấn công, và đường đi thẳng của Xe/Pháo. Thói quen này giúp tránh phần lớn lỗi nhập môn.',
      ),
    ],
    checkpoints: [
      'Biết vị trí cung Tướng của hai bên.',
      'Hiểu mục tiêu cuối cùng là chiếu bí.',
      'Bắt đầu quan sát đường thẳng trước khi đi quân.',
    ],
  ),
  LearningLesson(
    id: 'b002',
    order: 2,
    titleVi: 'Tướng, Sĩ, Tượng',
    subtitleVi: 'Ba lớp phòng thủ quanh cung và các giới hạn không được quên.',
    levelLabel: 'Nhập môn',
    estimatedMinutes: 7,
    focusPieces: ['Tướng', 'Sĩ', 'Tượng'],
    sections: [
      LessonSection(
        title: 'Tướng đi trong cung',
        body:
            'Tướng chỉ đi từng ô ngang hoặc dọc trong cung. Hai Tướng không được nhìn thẳng nhau trên cùng một cột nếu không có quân nào chắn giữa.',
        bullets: [
          'Không đưa Tướng ra khỏi cung.',
          'Luôn kiểm tra luật chống Tướng trước khi mở cột giữa.',
        ],
      ),
      LessonSection(
        title: 'Sĩ và Tượng giữ nhà',
        body:
            'Sĩ đi chéo một ô trong cung, còn Tượng đi chéo hai ô và không qua sông. Nếu điểm giữa đường chéo của Tượng bị chặn, Tượng không thể đi.',
        bullets: [
          'Sĩ giữ các điểm chéo quanh Tướng.',
          'Tượng mạnh khi còn đủ cặp và không bị chặn mắt.',
        ],
      ),
    ],
    checkpoints: [
      'Nhớ Tướng và Sĩ không rời cung.',
      'Nhớ Tượng không qua sông.',
      'Biết kiểm tra tình huống hai Tướng đối mặt.',
    ],
  ),
  LearningLesson(
    id: 'b003',
    order: 3,
    titleVi: 'Xe: sức mạnh đường thẳng',
    subtitleVi: 'Quân dễ hiểu nhất nhưng quyết định rất nhiều tàn cục.',
    levelLabel: 'Cơ bản',
    estimatedMinutes: 6,
    focusPieces: ['Xe'],
    sections: [
      LessonSection(
        title: 'Xe đi ngang dọc',
        body:
            'Xe đi bao nhiêu ô cũng được theo hàng ngang hoặc cột dọc, miễn là đường đi không bị quân khác chặn. Vì vậy Xe thích các đường mở.',
        bullets: [
          'Xe càng thoáng đường càng mạnh.',
          'Một Xe ở hàng trống có thể vừa bắt quân vừa chiếu Tướng.',
        ],
      ),
      LessonSection(
        title: 'Ưu tiên của người mới',
        body:
            'Khi có Xe, hãy hỏi: Xe đang bị bắt không, Xe có bắt được quân không, và Xe có tạo chiếu an toàn không. Ba câu hỏi này đủ để giải nhiều bài vỡ lòng.',
      ),
    ],
    checkpoints: [
      'Tìm được đường ngang/dọc sạch cho Xe.',
      'Biết dùng Xe để bắt quân treo.',
      'Không đưa Xe vào ô bị quân mạnh hơn bắt lại vô ích.',
    ],
    practicePuzzleIds: ['p001', 'p004', 'p008'],
  ),
  LearningLesson(
    id: 'b004',
    order: 4,
    titleVi: 'Pháo: cần ngòi để ăn quân',
    subtitleVi: 'Hiểu khác biệt giữa nước đi thường và nước ăn của Pháo.',
    levelLabel: 'Cơ bản',
    estimatedMinutes: 8,
    focusPieces: ['Pháo'],
    sections: [
      LessonSection(
        title: 'Đi như Xe, ăn khác Xe',
        body:
            'Pháo đi ngang dọc trên đường trống giống Xe. Nhưng khi ăn quân, giữa Pháo và mục tiêu phải có đúng một quân làm ngòi.',
        bullets: [
          'Không có ngòi thì Pháo không ăn được.',
          'Hai quân chắn trở lên thì Pháo cũng không ăn được.',
        ],
      ),
      LessonSection(
        title: 'Tự tạo ngòi',
        body:
            'Trong thực chiến, Tốt, Sĩ hoặc quân đối phương đều có thể thành ngòi Pháo. Người mới nên tập đếm số quân nằm giữa Pháo và mục tiêu.',
      ),
    ],
    checkpoints: [
      'Phân biệt nước đi thường và nước ăn của Pháo.',
      'Đếm đúng một quân ngòi khi Pháo bắt quân.',
      'Nhìn được đòn Pháo qua sông trong tàn cục.',
    ],
    practicePuzzleIds: ['p009', 'p014', 'p017'],
  ),
  LearningLesson(
    id: 'b005',
    order: 5,
    titleVi: 'Mã và chân Mã',
    subtitleVi: 'Quân linh hoạt, nhưng có thể bị khóa bởi một ô nhỏ.',
    levelLabel: 'Cơ bản',
    estimatedMinutes: 7,
    focusPieces: ['Mã'],
    sections: [
      LessonSection(
        title: 'Mã đi chữ nhật',
        body:
            'Mã đi một ô thẳng rồi một ô chéo, tạo hình gần giống chữ L. Nếu ô thẳng đầu tiên bị chặn, Mã không thể nhảy theo hướng đó.',
        bullets: [
          'Chân Mã nằm ở ô sát cạnh Mã theo hướng định đi.',
          'Chặn chân Mã là cách phòng thủ rất phổ biến.',
        ],
      ),
      LessonSection(
        title: 'Tập nhìn điểm đến',
        body:
            'Khi chọn Mã, hãy nhìn các ô mà Mã có thể tới và kiểm tra chân Mã trước. Đừng chỉ nhìn mục tiêu, vì một quân nhỏ có thể khóa cả đường nhảy.',
      ),
    ],
    checkpoints: [
      'Biết vì sao Mã không nhảy qua quân.',
      'Tìm được chân Mã bị chặn.',
      'Dùng Mã bắt quân ở thế thoáng.',
    ],
    practicePuzzleIds: ['p010', 'p018', 'p023'],
  ),
  LearningLesson(
    id: 'b006',
    order: 6,
    titleVi: 'Tốt qua sông',
    subtitleVi: 'Quân nhỏ nhưng có thể đổi nhịp tấn công rất mạnh.',
    levelLabel: 'Cơ bản',
    estimatedMinutes: 6,
    focusPieces: ['Tốt'],
    sections: [
      LessonSection(
        title: 'Trước và sau khi qua sông',
        body:
            'Tốt chỉ đi tiến từng ô. Sau khi qua sông, Tốt được đi ngang từng ô, nhưng vẫn không được đi lùi.',
        bullets: [
          'Tốt đỏ tiến về phía bên đen.',
          'Tốt đen tiến về phía bên đỏ.',
          'Tốt qua sông thường tạo đòn bắt ngang bất ngờ.',
        ],
      ),
      LessonSection(
        title: 'Đừng xem nhẹ Tốt',
        body:
            'Ở tàn cục, một Tốt đã qua sông có thể khóa cung Tướng, làm ngòi Pháo hoặc ép đối phương mất quân phòng thủ.',
      ),
    ],
    checkpoints: [
      'Nhớ Tốt không bao giờ đi lùi.',
      'Biết Tốt qua sông được đi ngang.',
      'Nhận ra Tốt có thể làm ngòi cho Pháo.',
    ],
    practicePuzzleIds: ['p011', 'p024'],
  ),
  LearningLesson(
    id: 'b007',
    order: 7,
    titleVi: 'Chiếu, chống chiếu, chiếu bí',
    subtitleVi: 'Các tình huống đặc biệt quyết định thắng thua.',
    levelLabel: 'Cơ bản',
    estimatedMinutes: 9,
    focusPieces: ['Chiếu', 'Chống Tướng'],
    sections: [
      LessonSection(
        title: 'Khi nào là chiếu',
        body:
            'Một bên bị chiếu khi Tướng đang bị quân đối phương tấn công. Bên bị chiếu phải xử lý ngay bằng cách chạy Tướng, ăn quân chiếu hoặc che đường chiếu.',
        bullets: [
          'Không được đi nước khiến Tướng mình vẫn bị chiếu.',
          'Nếu không còn nước hợp lệ để thoát chiếu, đó là chiếu bí.',
        ],
      ),
      LessonSection(
        title: 'Luật chống Tướng',
        body:
            'Hai Tướng không được đối mặt trực tiếp trên cùng một cột. Khi dời quân đang chắn giữa hai Tướng, luôn kiểm tra xem cột đó có bị mở trống không.',
      ),
    ],
    checkpoints: [
      'Biết ba cách thoát chiếu cơ bản.',
      'Phân biệt chiếu và chiếu bí.',
      'Không mở mặt Tướng bất cẩn.',
    ],
    practicePuzzleIds: ['p003', 'p005'],
  ),
  LearningLesson(
    id: 'b008',
    order: 8,
    titleVi: 'Thói quen một nước tốt',
    subtitleVi: 'Một checklist ngắn trước khi chuyển sang luyện tàn cục.',
    levelLabel: 'Ôn tập',
    estimatedMinutes: 6,
    focusPieces: ['Ôn tập'],
    sections: [
      LessonSection(
        title: 'Checklist 5 giây',
        body:
            'Trước mỗi nước đi, hãy tự hỏi: Tướng mình có an toàn không? Quân nào đang bị treo? Nước này có chiếu, bắt quân, hay tạo đe dọa thật không?',
        bullets: [
          'An toàn Tướng trước.',
          'Bắt quân miễn phí nếu có.',
          'Ưu tiên nước vừa công vừa thủ.',
        ],
      ),
      LessonSection(
        title: 'Từ học sang luyện',
        body:
            'Sau khóa vỡ lòng, người chơi nên luyện các bài tàn cục ngắn. Mỗi bài giúp biến một luật đi quân thành phản xạ nhìn thế.',
      ),
    ],
    checkpoints: [
      'Có thói quen kiểm tra an toàn Tướng.',
      'Biết nhìn quân bị treo.',
      'Sẵn sàng luyện puzzle ngắn.',
    ],
    practicePuzzleIds: ['p012', 'p016', 'p025'],
  ),
];
