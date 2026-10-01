# v1.1 数据来源与使用记录

原始数据：HaGRID / HaGRIDv2，作者 Alexander Kapitanov、Karina Kvanchiani、Alexander Nagaev、Andrey Kraynov、Andrey Makhliarchuk、Maxim等，具体署名以原始项目和论文为准。

- [原始项目、论文引用与许可入口](https://github.com/hukenovs/hagrid)
- [原作者许可全文](https://github.com/hukenovs/hagrid/blob/master/license/en_us.pdf)：原项目标注 variant of CC BY-SA 4.0，具体使用遵循该全文；镜像宣称MIT不作为授权依据。
- [图片子集镜像](https://huggingface.co/datasets/ntsrigaud/hagrid-subset)：仅用作下载已有公开图像的来源。
- [原始带关键点标注压缩包](https://rndml-team-cv.obs.ru-moscow-1.hc.sbercloud.ru/datasets/hagrid_v2/annotations_with_landmarks/annotations.zip)：实际仅保留所需图片的bboxes、labels、user_id和原始split，不使用关键点/人口统计预测。

映射：fist=拳头，peace=剪刀，palm=布，ok=OK，like=点赞；no_gesture和不与标注手框重叠的角落背景作为无有效手势负样本。镜像原始CSV的分组只用于定位下载路径；训练分组重新匹配原作者train/val/test和user_id，并强制验证人员集合不相交。

处理：以手框中心扩展为边长1.45倍最大框边的正方形，转灰度，区域平均缩至128×128；训练/验证输入再区域平均为64×64。超出图像部分由Pillow裁剪补0。该输入契约要求板端手部放在中央512×512区域、手约占方框三分之二，并不包含全画面手检测。

`data/manifest.json`记录每张派生图像的来源URL、原图SHA256、原始ID、user_id、类别及分组；同源手部和背景始终留在同一分组。`data/failures.json`记录未下载项，不把缺失样本计入完成数。`data/summary.json`记录实际数量；`artifacts/validation_report.json`记录本次独立测试结果，不能视为AR0135实拍精度。

本次仅在用户本地工作区做研究验证，没有上传或发布数据集、模型、照片。分享派生数据或模型前保留原始来源与许可文件，并核对原作者具体许可要求。
