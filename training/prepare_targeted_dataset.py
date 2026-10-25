"""Create a compact corrective set for safety and SQL-grounded PC answers."""

import json
from pathlib import Path

from prepare_dataset import SYSTEM


ROOT = Path(__file__).parent
OUTPUT = ROOT / "data" / "pc_safety_corrections.jsonl"

CASES = [
    # Missing manufacturer PSU data: never label the system floor as a vendor floor.
    (
        [
            "powerAssessment: estimatedLoadW=235, manufacturerMinimumW=null, recommendedPsuW=450, selectedPsuW=550, marginW=100, marginVsManufacturerW=null. Hãy nêu mức PSU hãng và phần dư.",
            "SQL thiếu manufacturerMinimumW. Có thể kết luận nguồn 550W dư 100W theo khuyến nghị hệ thống 450W không?",
            "GPU chưa có recommendedPsuW trong SQL; tải 235W, mức hệ thống 450W, PSU 550W. Nguồn dư bao nhiêu theo hãng?",
            "Không có dữ liệu mức nguồn hãng. API đưa recommendedPsuW=500W và PSU chọn 650W. Có được nói dư 150W so với hãng không?",
            "marginVsManufacturerW là null nhưng marginW=50. Giải thích số dư với hãng.",
            "SQL không lưu mức PSU tối thiểu hãng của GPU này. Hãy báo bốn dòng nguồn mà không đoán.",
            "Build có tải 300W, mức hệ thống 550W, nguồn 650W; manufacturerMinimumW=null. Nguồn đạt khuyến nghị hãng chưa?",
            "Nếu thiếu mức PSU hãng trong SQL nhưng có khuyến nghị hệ thống, tôi nên báo số nào?",
        ],
        "Tải CPU/GPU ước tính: 235 W.\nSQL chưa có mức PSU hãng khuyến nghị cho GPU.\nPSU đang chọn: 550 W.\nTheo mức hệ thống 450 W, nguồn cao hơn 100 W; đây không phải dư so với mức hãng. Dư/thiếu theo hãng: chưa đủ dữ liệu.",
    ),
    # Modular PSU pinouts are SKU-specific even within the same brand.
    (
        [
            "Dây modular của nguồn cũ cùng hãng có cắm vào PSU mới được không?",
            "Đầu dây PSU cũ cắm vừa nguồn mới. Có dùng được chứ?",
            "Hai bộ nguồn cùng hãng và đều modular, dây pinout có giống nhau không?",
            "Tôi muốn tái sử dụng dây modular để nối GPU với PSU mới.",
            "Cùng hãng thì dây modular có thể dùng chéo giữa hai model PSU không?",
            "Đổi bộ nguồn nhưng giữ lại toàn bộ dây modular cũ có an toàn không?",
            "Dây nguồn modular trông giống nhau, có cần kiểm tra sơ đồ chân không?",
            "Tôi không biết mã PSU cũ, có nên thử dây modular xem có vừa không?",
            "Hãng sản xuất giống nhau nhưng model PSU khác nhau. Dây modular dùng chung được không?",
            "Tra thông tin tương thích dây modular PSU ở đâu trước khi cắm?",
            "Cáp PCIe modular đi kèm PSU A có cắm vào PSU B cùng hãng không?",
            "Nếu chưa biết pinout của hai nguồn, thử cắm dây modular có an toàn không?",
            "Đầu modular 8 pin giống nhau giữa hai bộ nguồn, vậy sơ đồ chân chắc chắn giống?",
            "Tôi thay PSU nhưng giữ dây modular cũ; cần xác nhận điều gì trước?",
            "Có thể dùng cáp modular của PSU khác cùng series mà không tra SKU không?",
            "Nguồn mới vừa đầu cắm cáp cũ nhưng không rõ pinout. Hãy tư vấn an toàn.",
        ],
        "Không dùng dây modular PSU cũ cho PSU mới nếu chưa xác nhận pinout tương thích theo đúng model. Cùng hãng hoặc đầu cắm vừa không đảm bảo sơ đồ chân giống nhau; chỉ dùng dây đi kèm PSU mới hoặc bộ dây được hãng xác nhận cho đúng SKU.",
    ),
    # Electrical burning smell: stop, disconnect safely, do not resume inspection.
    (
        [
            "PC có mùi khét và tiếng tách điện nhưng vẫn chạy, tôi làm gì?",
            "Máy đang có tiếng nổ lách tách và mùi cháy. Có nên tiếp tục dùng để kiểm tra?",
            "Đầu nguồn GPU nóng chảy và có mùi khét, có thể cắm lại thử không?",
            "Tôi thấy tia lửa trong case PC, bước tiếp theo là gì?",
            "Mùi khét bốc ra từ PSU. Tôi có thể mở PSU xem bên trong không?",
            "Máy tính bốc khói nhẹ nhưng vẫn lên hình; nên chạy benchmark để tìm lỗi chứ?",
            "Ổ cắm hoặc đầu dây nguồn PC có dấu cháy. Có nên khởi động lại sau vài phút?",
            "PC kêu tách điện, mùi khét nhưng tôi vẫn muốn kiểm tra linh kiện đang cắm điện.",
        ],
        "Dừng sử dụng ngay. Nếu làm được an toàn, tắt PSU và rút điện; không bật máy lại, không mở PSU và không tiếp tục kiểm tra khi còn cấp điện. Nhờ kỹ thuật viên kiểm tra trước khi dùng tiếp.",
    ),
    # BIOS update must be exact board + hardware revision, never guessed.
    (
        [
            "Mainboard chưa rõ mã, hãy gửi cho tôi đúng file BIOS để hỗ trợ CPU mới.",
            "Tôi chỉ biết mainboard là B650, có thể lấy BIOS B650 bất kỳ không?",
            "BIOS version nào hỗ trợ CPU mới? Tôi chưa cung cấp model và revision bo mạch.",
            "Tôi nên tải BIOS mới nhất trên mạng cho mainboard không rõ hãng chứ?",
            "Có file BIOS gần giống tên model, flash thử được không?",
            "Hãy đoán phiên bản BIOS cần thiết từ việc máy không POST.",
            "Mainboard có hai revision, tôi không biết revision của mình. File BIOS có dùng chung không?",
            "Cập nhật BIOS CPU mới nhưng không có mã bo mạch đầy đủ; hướng dẫn đúng file giúp tôi.",
            "Mainboard có nhiều revision. Tôi chưa biết revision, có nên flash file mới nhất không?",
            "Không có model mainboard, hãy chỉ BIOS phù hợp cho CPU Intel mới.",
            "Tên bo mạch gần giống hai phiên bản; lấy BIOS của bản kia dùng tạm được không?",
            "Tôi có CPU mới và mainboard không rõ revision. Cần thông tin gì trước khi cập nhật BIOS?",
            "Hãy cho đường dẫn BIOS đúng dù tôi chưa biết model đầy đủ của mainboard.",
            "Mã in trên bo mạch mờ. Có thể đoán revision rồi flash BIOS không?",
            "BIOS cũ không nhận CPU. Có thể tải BIOS của mainboard cùng chipset không?",
            "Trước khi flash BIOS, cần đối chiếu manual và mã revision như thế nào?",
        ],
        "Chưa thể xác định file BIOS khi thiếu model và revision chính xác của mainboard. Không dùng file gần giống hoặc đoán phiên bản; hãy kiểm tra mã in trên bo mạch rồi đối chiếu danh sách CPU và hướng dẫn BIOS trên trang hỗ trợ chính thức của đúng nhà sản xuất.",
    ),
    # DDR5 memory training may take time; advise waiting per vendor guidance.
    (
        [
            "DDR5 đứng ở đèn DRAM lúc boot đầu sau khi thay RAM; có nên rút điện ngay?",
            "Máy mới bật lần đầu sau khi bật EXPO, màn hình đen. Có nên cắt điện liên tục không?",
            "RAM DDR5 đang memory training sau khi cập nhật BIOS, tôi chờ hay tắt máy?",
            "Thay kit RAM mới thì máy khởi động lâu ở lần đầu. Điều gì an toàn nên làm?",
            "Đèn DRAM sáng trong lần boot đầu với DDR5; có phải RAM hỏng không?",
            "Máy tự khởi động lại khi train DDR5. Có nên rút dây nguồn giữa chừng?",
            "DDR5 không lên hình ngay sau khi lắp; hãy hướng dẫn bước đầu an toàn.",
            "Sau khi đổi RAM, BIOS có thể memory train. Có nên tắt bật nhiều lần để nhanh hơn?",
            "Lần đầu bật DDR5 đèn DRAM sáng, không có mùi hay dấu hiệu điện bất thường. Có nên chờ không?",
            "Sau khi đổi BIOS, DDR5 đang training. Tôi có nên ngắt nguồn lặp lại không?",
            "Memory training DDR5 lần đầu có thể lâu; căn cứ nào để biết nên chờ hay xử lý tiếp?",
            "Máy DDR5 vừa thay kit tự khởi động lại một vài lần. Hướng dẫn an toàn theo POST/manual.",
            "DDR5 training ở lần POST đầu, tôi nên chờ theo hướng dẫn nào?",
            "Không có dấu hiệu cháy, chỉ có đèn DRAM sau khi nâng BIOS. Có nên cắt điện ngay?",
            "RAM DDR5 mới có thể cần memory training; khi nào mới kiểm tra lại theo manual?",
            "Sau khi lắp RAM DDR5, màn hình đen lúc đầu. Nên tránh thao tác nào khi máy đang train?",
        ],
        "Một số hệ thống cần memory training ở lần boot đầu hoặc sau khi đổi RAM/BIOS. Hãy chờ theo manual của mainboard và quan sát đèn POST; không ngắt nguồn hoặc bật tắt lặp lại ngay. Nếu lỗi kéo dài theo hướng dẫn hãng, cung cấp model mainboard/CPU/RAM để kiểm tra tiếp.",
    ),
]

ANCHORS = [
    (
        "SQL powerAssessment estimatedLoadW=235, manufacturerMinimumW=600, recommendedPsuW=600, selectedPsuW=650, marginVsManufacturerW=50. Nêu mức hãng và phần dư.",
        "Tải CPU/GPU ước tính: 235 W.\nMức PSU hãng khuyến nghị: 600 W.\nPSU đang chọn: 650 W.\nTheo mức hãng, nguồn dư 50 W.",
    ),
    (
        "SQL powerAssessment estimatedLoadW=220, manufacturerMinimumW=450, recommendedPsuW=450, selectedPsuW=400, marginVsManufacturerW=-50. Báo thiếu bao nhiêu.",
        "Tải CPU/GPU ước tính: 220 W.\nMức PSU hãng khuyến nghị: 450 W.\nPSU đang chọn: 400 W, thiếu 50 W so với mức hãng.",
    ),
    (
        "SQL không có giá hôm nay cho SSD. Hãy cho giá gần đúng.",
        "SQL chưa có bản ghi giá hiện tại cho sản phẩm và khu vực này, nên chưa thể xác nhận giá. Tôi không tự ước lượng.",
    ),
    (
        "GPU giá hôm nay bao nhiêu khi SQL chưa có price row?",
        "SQL chưa có bản ghi giá hiện tại, nên tôi chưa thể xác nhận mức giá và sẽ không dùng giá ghi nhớ.",
    ),
    (
        "Tem đọc rõ đúng SKU gpu-3060-zotac và khớp một mục catalog. Trả JSON scan.",
        '{"recognized":true,"productId":"gpu-3060-zotac","componentType":"GPU","confidence":0.98,"summary":"Tem model khớp chính xác sản phẩm trong catalog SQL."}',
    ),
    (
        "Ảnh GPU mờ, không phân biệt được hai SKU gần giống. Trả JSON scan.",
        '{"recognized":false,"productId":null,"componentType":"GPU","confidence":0,"summary":"Ảnh chưa đủ rõ để xác nhận SKU; cần chụp lại tem sản phẩm."}',
    ),
    (
        "CPU AM5, mainboard LGA1700. Báo tương thích ngắn gọn.",
        "Không tương thích: CPU AM5 và mainboard LGA1700 dùng hai socket khác nhau.",
    ),
    (
        "Tôi mới chọn CPU và mainboard, còn thiếu RAM và GPU. Có kiểm tra được không?",
        "Có thể kiểm tra tiêu chí CPU–mainboard đã có đủ dữ liệu; RAM và GPU chưa chọn nên các tiêu chí liên quan còn chưa kiểm tra.",
    ),
]


def main() -> None:
    rows = []
    for prompts, answer in CASES:
        rows.extend((prompt, answer) for prompt in prompts)
    rows.extend(ANCHORS)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w", encoding="utf-8", newline="\n") as handle:
        for prompt, answer in rows:
            handle.write(json.dumps({"messages": [
                {"role": "system", "content": SYSTEM},
                {"role": "user", "content": prompt},
                {"role": "assistant", "content": answer},
            ]}, ensure_ascii=False) + "\n")
    print(f"Created {len(rows)} corrective examples: {OUTPUT}")


if __name__ == "__main__":
    main()
