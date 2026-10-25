"""Create focused, varied safety corrections for adapter v10."""

import json
from pathlib import Path

from prepare_dataset import SYSTEM


ROOT = Path(__file__).parent
OUTPUT = ROOT / "data" / "pc_safety_v10.jsonl"

CASES = [
    (
        [
            "Dây modular của PSU cũ cùng hãng có dùng cho bộ nguồn mới được không?",
            "Đầu cắm vừa khít, có thể thử bật máy với dây PSU modular cũ không?",
            "Cáp PCIe modular từ PSU A có cắm vào PSU B cùng hãng không?",
            "Tôi không nhớ model PSU cũ. Làm sao biết dây modular đó dùng được?",
            "Dây modular trông giống nhau và cùng hãng, pinout có chắc giống không?",
            "Có dùng dây modular của cùng series PSU nhưng khác SKU được chứ?",
            "Đổi PSU, tôi giữ lại dây modular cũ để nối GPU nhé?",
            "Tra thông tin gì trước khi dùng chung dây modular giữa hai PSU?",
            "Cáp modular cũ có thể làm hỏng GPU nếu pinout khác không?",
            "Tôi chưa biết mã hai PSU, có cách cắm thử an toàn không?",
            "Bộ dây modular rời ghi cùng hãng, nhưng không rõ dòng PSU tương thích.",
            "PSU mới thiếu cáp, dây của PSU cũ cùng hãng dùng tạm được không?",
            "Đầu modular 8-pin giống nhau có nghĩa sơ đồ chân luôn giống nhau?",
            "Tôi muốn tái sử dụng cáp CPU modular nhưng khác mã nguồn.",
            "Dây modular cũ có nhãn mờ; có nên cắm vào PSU mới để kiểm tra?",
            "Điều kiện nào phải xác minh trước khi dùng cáp modular với PSU khác?",
        ],
        [
            "Không dùng dây modular cũ cho đến khi hãng xác nhận pinout cho đúng model PSU. Cùng hãng, cùng series hoặc đầu cắm vừa không chứng minh sơ đồ chân giống nhau. Ưu tiên dây đi kèm PSU mới hoặc dây thay thế được hãng xác nhận cho đúng SKU.",
            "Đừng thử bật máy. Hãy kiểm tra mã chính xác của cả hai PSU và bảng tương thích cáp/pinout do nhà sản xuất công bố. Chỉ dùng cáp được xác nhận cho đúng model; hình dáng đầu cắm không đủ để kết luận an toàn.",
            "Chưa thể xác nhận nếu thiếu model PSU và pinout. Không cắm thử; dùng bộ cáp đi kèm PSU B hoặc hỏi hãng về mã cáp tương thích với đúng SKU PSU B.",
            "Cáp modular có thể khác sơ đồ chân giữa các model. Không dùng dây cũ cho đến khi đối chiếu model PSU và xác nhận tương thích từ tài liệu/hỗ trợ chính hãng.",
        ],
    ),
    (
        [
            "Mainboard chưa rõ model và revision, hãy gửi đúng file BIOS cho CPU mới.",
            "Tôi chỉ biết bo mạch dùng chipset B650; BIOS của B650 nào cũng được không?",
            "Có hai revision mainboard gần giống. Tôi không rõ bản nào, cứ flash BIOS mới nhất nhé?",
            "Máy không POST, hãy đoán file BIOS cần flash từ tên CPU.",
            "CPU mới cần BIOS nào nếu chưa có mã đầy đủ của mainboard?",
            "Tôi tìm thấy BIOS trên diễn đàn, tên gần giống bo mạch của mình.",
            "Model in trên mainboard bị mờ. Có thể chọn BIOS của cùng hãng và chipset không?",
            "Trước khi cập nhật BIOS, cần xác minh thông tin nào trên bo mạch?",
            "Mainboard có nhiều revision; file BIOS bản khác có thể dùng tạm không?",
            "Tôi chưa biết revision nhưng cửa hàng nói cứ flash bản mới nhất.",
            "Hãy hướng dẫn flash BIOS cho mainboard không rõ mã chính xác.",
            "CPU chưa chạy với BIOS hiện tại; tải BIOS của mainboard cùng socket nhé?",
            "Có thể bỏ qua danh sách CPU hỗ trợ khi cập nhật BIOS không?",
            "Tôi cần đúng BIOS nhưng chỉ cung cấp được tên chipset và hãng.",
            "BIOS gần giống tên model xuất hiện trên trang hãng, có nên dùng không?",
            "Thiếu model/revision mainboard thì có thể xác nhận file BIOS bằng cách nào?",
        ],
        [
            "Chưa thể chỉ đúng file BIOS khi thiếu model và revision chính xác của mainboard. Không flash file gần giống. Đọc mã in trên bo mạch, rồi đối chiếu trang hỗ trợ chính hãng, danh sách CPU hỗ trợ và hướng dẫn cho đúng revision.",
            "Chipset B650 không đủ để xác định BIOS. Cần mã mainboard đầy đủ và revision, sau đó kiểm tra trang hỗ trợ/manual của đúng nhà sản xuất. Không tải hoặc flash file của bo mạch khác.",
            "Không nên cập nhật khi chưa biết revision. Xác nhận model/revision trên PCB hoặc hộp, đối chiếu danh sách CPU và quy trình BIOS trên trang hỗ trợ chính thức của model đó.",
            "Tôi không thể đoán file BIOS từ CPU hoặc chipset. Hãy cung cấp model và revision mainboard; chỉ dùng tệp từ trang hỗ trợ chính thức ứng với đúng bo mạch.",
        ],
    ),
    (
        [
            "PC mới dùng DDR5 đang memory training lần boot đầu, có nên rút điện ngay?",
            "Đèn DRAM sáng sau khi bật máy lần đầu. Không có mùi khét. Tôi nên chờ hay tắt?",
            "Sau khi bật EXPO, máy khởi động lại vài lần và màn hình đen. Cắt điện liên tục nhé?",
            "DDR5 training sau cập nhật BIOS có thể mất thời gian; căn cứ nào để chờ?",
            "Máy đứng ở POST memory training sau khi thay RAM. Bước an toàn đầu tiên là gì?",
            "Lần boot DDR5 đầu tiên lâu hơn bình thường, có nên bật tắt PSU liên tục?",
            "Mainboard đang báo đèn DRAM trong lần khởi động đầu, chưa thấy dấu hiệu nguy hiểm.",
            "Sau khi thay kit DDR5, hệ thống tự restart khi train RAM. Có rút dây nguồn không?",
            "Máy chưa lên hình ngay sau khi lắp RAM DDR5. Có nên chờ theo manual?",
            "DDR5 training kéo dài. Khi nào mới dừng chờ và kiểm tra tiếp?",
            "Đèn POST DRAM nhấp nháy ở boot đầu; có nên tháo RAM khi máy đang bật?",
            "Sau khi đổi BIOS, RAM đang training. Hướng dẫn cách tránh làm gián đoạn.",
            "Không có mùi cháy, chỉ đèn DRAM sau khi lắp RAM. Tôi nên làm gì trước?",
            "Memory training thất bại vài lần; tôi có cắt điện khi máy tự khởi động lại không?",
            "Manual mainboard quy định thời gian memory training. Có nên chờ đủ thời gian đó?",
            "DDR5 boot đầu đen màn hình nhưng đèn POST đang báo DRAM, xử lý thế nào?",
        ],
        [
            "DDR5 có thể memory train ở lần boot đầu hoặc sau khi đổi RAM/BIOS. Nếu không có mùi khét, tia lửa hay dấu hiệu điện nguy hiểm, hãy chờ theo manual của mainboard và quan sát đèn POST; không ngắt nguồn hoặc bật tắt lặp lại. Nếu quá thời gian hãng hướng dẫn, gửi model mainboard/CPU/RAM để kiểm tra tiếp.",
            "Chưa cần rút điện chỉ vì đèn DRAM sáng ở lần boot đầu. Chờ thời gian memory training theo manual và theo dõi POST. Không tháo RAM khi máy đang chạy; nếu quá giới hạn hướng dẫn, tắt máy theo quy trình rồi kiểm tra từng thanh/khe theo manual.",
            "Không cắt điện liên tục trong khi hệ thống đang memory training bình thường. Để máy hoàn tất theo thời gian hãng nêu. Nếu training lặp quá giới hạn hoặc có dấu hiệu nguy hiểm như mùi khét/tia lửa, dừng và xử lý an toàn theo tài liệu/kỹ thuật viên.",
            "Hãy chờ đủ thời gian POST/memory training quy định cho đúng mainboard. Sau đó nếu vẫn lỗi, tắt máy bình thường, ngắt nguồn trước khi kiểm tra RAM theo khe ưu tiên trong manual; không rút/cắm linh kiện khi máy có điện.",
        ],
    ),
    (
        [
            "Máy có mùi khét và vẫn còn chạy. Tôi chờ 15 phút rồi bật lại thử được không?",
            "PSU bốc mùi cháy nhưng quạt còn quay, có thể chạy thêm để sao lưu dữ liệu không?",
            "Có tia lửa ở dây GPU. Rút điện rồi cắm lại sau khi chờ có an toàn không?",
            "Đầu nguồn nóng chảy, tôi muốn bật lại để xác định linh kiện hỏng.",
            "PC kêu tách điện, mùi khét. Có nên mở PSU xem tụ không?",
            "Máy có khói nhẹ nhưng đã hết mùi. Bật lại kiểm tra nhanh được chứ?",
            "Nếu rút điện rồi, có thể cắm lại sau vài phút để thử lần nữa không?",
            "Ổ điện có dấu cháy khi cắm PC. Chuyển sang ổ khác và thử chạy nhé?",
            "Nguồn có tiếng nổ nhỏ và mùi khét, cần làm gì ngay?",
            "Mùi cháy thoáng qua rồi hết; có nên tiếp tục dùng máy bình thường?",
            "Dây nguồn đổi màu và có mùi. Có thể thay dây rồi bật lại ngay không?",
            "Tia lửa xuất hiện trong case, tôi có thể kiểm tra khi PSU vẫn bật không?",
        ],
        [
            "Dừng sử dụng và không bật lại để thử. Nếu làm được an toàn, ngắt nguồn/tắt PSU và rút điện; không mở PSU, không chạm vào phần cháy và không kiểm tra khi còn điện. Nhờ kỹ thuật viên kiểm tra trước khi cấp điện lại.",
            "Không tiếp tục chạy để sao lưu và không cắm thử lại, kể cả sau khi chờ. Ngắt điện nếu an toàn, tránh chạm phần nóng/cháy, không mở PSU; chuyển thiết bị cho kỹ thuật viên kiểm tra.",
            "Tia lửa hoặc mùi khét là dấu hiệu nguy hiểm: dừng ngay, ngắt điện nếu an toàn và không cấp điện lại. Không tự thử dây/ổ khác để kiểm tra; cần kỹ thuật viên xác nhận nguyên nhân trước khi dùng.",
            "Không bật máy lại sau khi có dấu cháy. Tắt/ngắt nguồn nếu an toàn, không mở PSU hoặc tháo dây khi còn điện, rồi liên hệ kỹ thuật viên hoặc bảo hành để kiểm tra.",
        ],
    ),
]


def main() -> None:
    rows = []
    for prompts, answers in CASES:
        for index, prompt in enumerate(prompts):
            rows.append({
                "messages": [
                    {"role": "system", "content": SYSTEM},
                    {"role": "user", "content": prompt},
                    {"role": "assistant", "content": answers[index % len(answers)]},
                ]
            })
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w", encoding="utf-8", newline="\n") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")
    print(f"Created {len(rows)} safety examples: {OUTPUT}")


if __name__ == "__main__":
    main()
