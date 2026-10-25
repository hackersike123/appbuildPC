"""Build high-signal PC safety corrections while preserving known-good behavior."""

import json
from pathlib import Path

from prepare_dataset import SYSTEM


ROOT = Path(__file__).parent
OUTPUT = ROOT / "data" / "pc_safety_v12.jsonl"

CASES = [
    (
        [
            "Dây modular của PSU cũ cùng hãng có dùng cho PSU mới không?",
            "Đầu cắm cáp cũ vừa với PSU mới; bật thử được chứ?",
            "Hai bộ nguồn cùng hãng, cáp modular có chung pinout không?",
            "Tôi không biết model nguồn cũ; có thể dùng dây modular đó không?",
            "Cáp PCIe modular của PSU A cắm sang PSU B được không?",
            "Đổi PSU nhưng giữ dây modular cũ thì cần kiểm tra gì?",
            "Các đầu cắm modular giống nhau, sơ đồ chân chắc chắn giống chứ?",
            "Có thể thử bật máy để xem dây PSU modular cũ chạy không?",
            "Dùng dây của cùng series PSU nhưng khác mã có an toàn không?",
            "Hãng nào xác nhận cáp modular này tương thích đúng PSU mới?",
            "Cáp modular không rõ SKU, tôi nên cắm vào đâu để thử?",
            "PSU mới thiếu dây; dây cũ cùng hãng có dùng tạm được không?",
        ],
        "Không dùng hoặc cắm thử dây modular cũ. Pinout cáp phải được xác nhận cho đúng model và revision của PSU mới; cùng hãng, cùng series hoặc đầu cắm vừa không chứng minh tương thích. Chỉ dùng dây đi kèm PSU mới hoặc mã cáp được hãng liệt kê tương thích với chính xác SKU PSU đó.",
    ),
    (
        [
            "Hãy đưa đúng file BIOS cho CPU mới; tôi chưa biết model và revision mainboard.",
            "Mainboard chipset B650, chọn BIOS nào cũng được không?",
            "Tôi không rõ revision bo mạch; có flash bản BIOS mới nhất được không?",
            "Hai model mainboard tên gần giống nhau, dùng chung BIOS nhé?",
            "Máy không POST, hãy đoán BIOS phù hợp từ CPU.",
            "Cần BIOS hỗ trợ CPU mới nhưng chỉ biết hãng mainboard.",
            "Tôi tìm thấy file BIOS trên diễn đàn có tên gần với bo mạch.",
            "Thiếu mã mainboard, bạn chọn giúp BIOS theo socket được không?",
            "Trước khi cập nhật BIOS cần xác nhận chính xác thông tin nào?",
            "Model mainboard bị mờ trên ảnh, có thể flash file của cùng chipset không?",
            "BIOS cho revision khác có thể dùng tạm nếu cùng dòng mainboard không?",
            "Tôi chưa biết revision; hãy hướng dẫn cách flash file gần đúng.",
        ],
        "Chưa thể chọn BIOS khi thiếu model mainboard và revision chính xác; chipset B650 hoặc model CPU không đủ để xác định. Không tải hay flash file đoán/gần giống. Đọc model và revision in trên bo mạch, rồi vào trang hỗ trợ chính thức của đúng model/revision để đối chiếu CPU Support List, BIOS tối thiểu và hướng dẫn trong manual.",
    ),
    (
        [
            "DDR5 đang memory training ở lần boot đầu, có nên cắt điện ngay?",
            "Đèn DRAM sáng sau khi lắp RAM mới, không có mùi khét. Tôi làm gì?",
            "Máy tự khởi động lại vài lần khi train DDR5; có rút nguồn lặp lại không?",
            "Memory training sau khi cập nhật BIOS thường cần chờ theo hướng dẫn nào?",
            "Màn hình đen ở boot đầu, đèn POST báo DRAM. Có nên bật tắt liên tục?",
            "DDR5 training lâu hơn bình thường nhưng không có dấu hiệu cháy, xử lý sao?",
            "Có thể tháo thanh RAM trong khi máy đang memory training không?",
            "Sau khi bật EXPO máy train RAM; có rút dây điện ngay để dừng không?",
            "Khi nào nên dừng chờ memory training và kiểm tra RAM?",
            "Máy mới lắp DDR5 đứng ở đèn DRAM. Có thể chờ theo manual không?",
            "Nếu memory training quá thời gian manual, bước tiếp theo an toàn là gì?",
            "DDR5 đang POST lần đầu; tôi có nên ngắt nguồn rồi cắm lại nhiều lần?",
        ],
        "Nếu chỉ đang memory training DDR5 ở lần boot đầu và không có mùi khét, khói hoặc tia lửa, hãy để máy tự hoàn tất và chờ đúng khoảng thời gian ghi trong manual của mainboard; theo dõi đèn POST. Không ngắt điện, nhấn giữ nút nguồn, bật/tắt lặp lại hoặc tháo RAM khi máy đang chạy. Chỉ khi vượt thời gian manual, tắt máy theo quy trình của hãng; sau khi máy tắt hẳn mới ngắt điện và kiểm tra theo manual. Nếu có khói, mùi khét hoặc tia lửa, dừng ngay và rút điện nếu an toàn.",
    ),
    (
        [
            "PC có mùi khét nhưng vẫn chạy. Chờ 15 phút rồi bật lại thử được không?",
            "PSU bốc mùi cháy, tôi có thể tiếp tục chạy để sao lưu dữ liệu không?",
            "Có tia lửa ở dây GPU. Rút điện rồi cắm lại kiểm tra nhé?",
            "Đầu cắm chảy nhựa; bật máy lại để tìm linh kiện hỏng có an toàn không?",
            "Mùi khét hết rồi, có nên cắm điện và chạy thử lần nữa không?",
            "PC có tiếng tách điện và khói nhẹ. Tôi nên làm gì ngay?",
        ],
        "Dừng sử dụng ngay. Không bật lại, cắm thử hoặc tiếp tục cấp điện. Nếu có thể làm an toàn mà không chạm phần nóng/cháy, tắt công tắc PSU và rút dây nguồn khỏi ổ điện; tránh tiếp xúc với khói hoặc linh kiện cháy. Không mở PSU hay tự kiểm tra khi còn điện. Đưa máy cho kỹ thuật viên kiểm tra trước khi cấp điện trở lại.",
    ),
]

ANCHORS = [
    (
        "powerAssessment: estimatedLoadW=235, manufacturerMinimumW=600, recommendedPsuW=600, selectedPsuW=650, marginVsManufacturerW=50. Nêu số liệu PSU.",
        "Tải CPU/GPU ước tính: 235 W.\nMức PSU hãng khuyến nghị: 600 W.\nPSU đang chọn: 650 W.\nTheo mức hãng, nguồn dư 50 W.",
    ),
    (
        "manufacturerMinimumW=null, recommendedPsuW=450, selectedPsuW=550, marginW=100, marginVsManufacturerW=null. Báo phần dư theo hãng.",
        "SQL chưa có mức PSU hãng khuyến nghị cho GPU nên chưa xác định được dư/thiếu theo hãng. Theo mức hệ thống 450 W, PSU 550 W cao hơn 100 W; đây không phải chênh lệch theo hãng.",
    ),
    (
        "CPU socket AM5, mainboard socket LGA1700. Kết luận tương thích.",
        "Không tương thích: CPU AM5 và mainboard LGA1700 dùng socket khác nhau.",
    ),
    (
        "SQL không có bản ghi giá hiện tại cho sản phẩm. Cho tôi giá hôm nay.",
        "SQL chưa có bản ghi giá hiện tại cho sản phẩm và khu vực này, nên chưa thể xác nhận giá. Tôi sẽ không tự ước lượng.",
    ),
    (
        "Tem đọc rõ đúng SKU gpu-3060-zotac và khớp duy nhất một sản phẩm catalog. Trả đúng JSON scan.",
        '{"recognized":true,"productId":"gpu-3060-zotac","componentType":"GPU","confidence":0.98,"summary":"Tem và mã sản phẩm khớp chính xác catalog SQL."}',
    ),
    (
        "Ảnh GPU mờ, có hai sản phẩm gần giống trong catalog. Trả đúng JSON scan.",
        '{"recognized":false,"productId":null,"componentType":"GPU","confidence":0,"summary":"Ảnh chưa đủ rõ để xác định SKU; cần chụp lại tem."}',
    ),
    *[
        ("Dây PSU cũ cùng hãng PSU mới, có thể cắm dùng không?", "Không dùng cáp modular cũ. Chỉ sử dụng nếu hãng xác nhận đúng mã cáp tương thích chính xác với model và revision PSU mới; cùng hãng hoặc vừa đầu cắm không đủ căn cứ."),
        ("PC có mùi khét, xử lý gì ngay?", "Dừng sử dụng, không bật lại. Nếu an toàn, tắt PSU và rút điện. Không mở PSU; nhờ kỹ thuật viên kiểm tra trước khi cấp điện lại."),
        ("Tôi cần file BIOS nhưng thiếu revision mainboard.", "Chưa thể xác định BIOS. Không đoán hoặc flash. Cần model và revision chính xác, rồi dùng trang hỗ trợ chính thức và manual của đúng bo mạch."),
        ("DDR5 memory training lần đầu, không có khói hay mùi khét; làm gì?", "Để máy tự hoàn tất và chờ theo manual của đúng mainboard, quan sát đèn POST. Không ngắt điện, bật/tắt liên tục hoặc tháo RAM khi máy đang chạy."),
    ]
]


def main() -> None:
    rows = []
    for prompts, answer in CASES:
        for prompt in prompts:
            rows.append((prompt, answer))
    rows.extend(ANCHORS)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w", encoding="utf-8", newline="\n") as handle:
        for prompt, answer in rows:
            handle.write(json.dumps({"messages": [
                {"role": "system", "content": SYSTEM},
                {"role": "user", "content": prompt},
                {"role": "assistant", "content": answer},
            ]}, ensure_ascii=False) + "\n")
    print(f"Created {len(rows)} focused examples: {OUTPUT}")


if __name__ == "__main__":
    main()
