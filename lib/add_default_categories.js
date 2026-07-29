const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

initializeApp({ credential: applicationDefault() });

const db = getFirestore();



// ข้อมูลหมวดหมู่เริ่มต้น
const defaultCategories = [
    {
      "category_name": "สัตว์ (Animals)",
      "words": [
        { "word": "Dog", "meaning": "หมา", "part_of_speech": "Noun" },
        { "word": "Cat", "meaning": "แมว", "part_of_speech": "Noun" },
        { "word": "Elephant", "meaning": "ช้าง", "part_of_speech": "Noun" },
        { "word": "Tiger", "meaning": "เสือ", "part_of_speech": "Noun" },
        { "word": "Lion", "meaning": "สิงโต", "part_of_speech": "Noun" },
        { "word": "Monkey", "meaning": "ลิง", "part_of_speech": "Noun" },
        { "word": "Horse", "meaning": "ม้า", "part_of_speech": "Noun" },
        { "word": "Bear", "meaning": "หมี", "part_of_speech": "Noun" },
        { "word": "Rabbit", "meaning": "กระต่าย", "part_of_speech": "Noun" },
        { "word": "Giraffe", "meaning": "ยีราฟ", "part_of_speech": "Noun" },
        { "word": "Wolf", "meaning": "หมาป่า", "part_of_speech": "Noun" },
        { "word": "Kangaroo", "meaning": "จิงโจ้", "part_of_speech": "Noun" },
        { "word": "Penguin", "meaning": "นกเพนกวิน", "part_of_speech": "Noun" },
        { "word": "Crocodile", "meaning": "จระเข้", "part_of_speech": "Noun" },
        { "word": "Snake", "meaning": "งู", "part_of_speech": "Noun" },
        { "word": "Frog", "meaning": "กบ", "part_of_speech": "Noun" },
        { "word": "Bird", "meaning": "นก", "part_of_speech": "Noun" },
        { "word": "Fish", "meaning": "ปลา", "part_of_speech": "Noun" },
        { "word": "Whale", "meaning": "วาฬ", "part_of_speech": "Noun" },
        { "word": "Shark", "meaning": "ฉลาม", "part_of_speech": "Noun" }
      ]
    },
    {
      "category_name": "อาหาร (Food & Drinks)",
      "words": [
        { "word": "Rice", "meaning": "ข้าว", "part_of_speech": "Noun" },
        { "word": "Coffee", "meaning": "กาแฟ", "part_of_speech": "Noun" },
        { "word": "Apple", "meaning": "แอปเปิ้ล", "part_of_speech": "Noun" },
        { "word": "Banana", "meaning": "กล้วย", "part_of_speech": "Noun" },
        { "word": "Tea", "meaning": "ชา", "part_of_speech": "Noun" },
        { "word": "Milk", "meaning": "นม", "part_of_speech": "Noun" },
        { "word": "Juice", "meaning": "น้ำผลไม้", "part_of_speech": "Noun" },
        { "word": "Cheese", "meaning": "ชีส", "part_of_speech": "Noun" },
        { "word": "Cake", "meaning": "เค้ก", "part_of_speech": "Noun" },
        { "word": "Bread", "meaning": "ขนมปัง", "part_of_speech": "Noun" },
        { "word": "Pasta", "meaning": "พาสต้า", "part_of_speech": "Noun" },
        { "word": "Pizza", "meaning": "พิซซ่า", "part_of_speech": "Noun" },
        { "word": "Ice cream", "meaning": "ไอศกรีม", "part_of_speech": "Noun" },
        { "word": "Steak", "meaning": "สเต็ก", "part_of_speech": "Noun" },
        { "word": "Sushi", "meaning": "ซูชิ", "part_of_speech": "Noun" },
        { "word": "Hotdog", "meaning": "ฮอทด็อก", "part_of_speech": "Noun" },
        { "word": "Soup", "meaning": "ซุป", "part_of_speech": "Noun" },
        { "word": "Noodle", "meaning": "ก๋วยเตี๋ยว", "part_of_speech": "Noun" },
        { "word": "Chicken", "meaning": "ไก่", "part_of_speech": "Noun" },
        { "word": "Fish", "meaning": "ปลา", "part_of_speech": "Noun" }
      ]
    },
    {
      "category_name": "สถานที่ (Places)",
      "words": [
        { "word": "School", "meaning": "โรงเรียน", "part_of_speech": "Noun" },
        { "word": "Hospital", "meaning": "โรงพยาบาล", "part_of_speech": "Noun" },
        { "word": "Restaurant", "meaning": "ร้านอาหาร", "part_of_speech": "Noun" },
        { "word": "Park", "meaning": "สวนสาธารณะ", "part_of_speech": "Noun" },
        { "word": "Library", "meaning": "ห้องสมุด", "part_of_speech": "Noun" },
        { "word": "Airport", "meaning": "สนามบิน", "part_of_speech": "Noun" },
        { "word": "Beach", "meaning": "ชายหาด", "part_of_speech": "Noun" },
        { "word": "Mountain", "meaning": "ภูเขา", "part_of_speech": "Noun" },
        { "word": "City", "meaning": "เมือง", "part_of_speech": "Noun" },
        { "word": "Village", "meaning": "หมู่บ้าน", "part_of_speech": "Noun" },
        { "word": "Bank", "meaning": "ธนาคาร", "part_of_speech": "Noun" },
        { "word": "Hotel", "meaning": "โรงแรม", "part_of_speech": "Noun" },
        { "word": "Store", "meaning": "ร้านค้า", "part_of_speech": "Noun" },
        { "word": "Museum", "meaning": "พิพิธภัณฑ์", "part_of_speech": "Noun" },
        { "word": "Factory", "meaning": "โรงงาน", "part_of_speech": "Noun" },
        { "word": "Office", "meaning": "สำนักงาน", "part_of_speech": "Noun" },
        { "word": "Supermarket", "meaning": "ซูเปอร์มาร์เก็ต", "part_of_speech": "Noun" },
        { "word": "Church", "meaning": "โบสถ์", "part_of_speech": "Noun" },
        { "word": "Temple", "meaning": "วัด", "part_of_speech": "Noun" }
      ]
    },
    {
      "category_name": "อาชีพ (Professions)",
      "words": [
        { "word": "Doctor", "meaning": "หมอ", "part_of_speech": "Noun" },
        { "word": "Teacher", "meaning": "ครู", "part_of_speech": "Noun" },
        { "word": "Engineer", "meaning": "วิศวกร", "part_of_speech": "Noun" },
        { "word": "Nurse", "meaning": "พยาบาล", "part_of_speech": "Noun" },
        { "word": "Chef", "meaning": "เชฟ", "part_of_speech": "Noun" },
        { "word": "Artist", "meaning": "ศิลปิน", "part_of_speech": "Noun" },
        { "word": "Scientist", "meaning": "นักวิทยาศาสตร์", "part_of_speech": "Noun" },
        { "word": "Writer", "meaning": "นักเขียน", "part_of_speech": "Noun" },
        { "word": "Lawyer", "meaning": "ทนายความ", "part_of_speech": "Noun" },
        { "word": "Driver", "meaning": "คนขับรถ", "part_of_speech": "Noun" },
        { "word": "Actor", "meaning": "นักแสดง", "part_of_speech": "Noun" },
        { "word": "Singer", "meaning": "นักร้อง", "part_of_speech": "Noun" },
        { "word": "Dancer", "meaning": "นักเต้น", "part_of_speech": "Noun" },
        { "word": "Photographer", "meaning": "ช่างภาพ", "part_of_speech": "Noun" },
        { "word": "Architect", "meaning": "สถาปนิก", "part_of_speech": "Noun" },
        { "word": "Programmer", "meaning": "โปรแกรมเมอร์", "part_of_speech": "Noun" },
        { "word": "Manager", "meaning": "ผู้จัดการ", "part_of_speech": "Noun" },
        { "word": "Farmer", "meaning": "ชาวนา", "part_of_speech": "Noun" },
        { "word": "Policeman", "meaning": "ตำรวจ", "part_of_speech": "Noun" }
      ]
    },
    {
        "category_name": "เครื่องมือ (Tools)",
        "words": [
          { "word": "Hammer", "meaning": "ค้อน", "part_of_speech": "Noun" },
          { "word": "Screwdriver", "meaning": "ไขควง", "part_of_speech": "Noun" },
          { "word": "Wrench", "meaning": "ประแจ", "part_of_speech": "Noun" },
          { "word": "Pliers", "meaning": "คีม", "part_of_speech": "Noun" },
          { "word": "Drill", "meaning": "สว่าน", "part_of_speech": "Noun" },
          { "word": "Saw", "meaning": "เลื่อย", "part_of_speech": "Noun" },
          { "word": "Tape measure", "meaning": "ไม้วัดระยะ", "part_of_speech": "Noun" },
          { "word": "Level", "meaning": "ระดับ", "part_of_speech": "Noun" },
          { "word": "Chisel", "meaning": "สกัด", "part_of_speech": "Noun" },
          { "word": "File", "meaning": "ไฟล์", "part_of_speech": "Noun" },
          { "word": "Knife", "meaning": "มีด", "part_of_speech": "Noun" },
          { "word": "Shovel", "meaning": "พลั่ว", "part_of_speech": "Noun" },
          { "word": "Pickaxe", "meaning": "ขวานค้อน", "part_of_speech": "Noun" },
          { "word": "Spanner", "meaning": "ประแจเลื่อน", "part_of_speech": "Noun" },
          { "word": "Nail", "meaning": "ตะปู", "part_of_speech": "Noun" },
          { "word": "Screw", "meaning": "สกรู", "part_of_speech": "Noun" },
          { "word": "Bolt", "meaning": "สลักเกลียว", "part_of_speech": "Noun" },
          { "word": "Ladder", "meaning": "บันได", "part_of_speech": "Noun" },
          { "word": "Bucket", "meaning": "ถัง", "part_of_speech": "Noun" },
          { "word": "Torch", "meaning": "ไฟฉาย", "part_of_speech": "Noun" }
        ]
      },
      {
        "category_name": "อารมณ์ (Emotions)",
        "words": [
          { "word": "Happy", "meaning": "มีความสุข", "part_of_speech": "Adjective" },
          { "word": "Sad", "meaning": "เศร้า", "part_of_speech": "Adjective" },
          { "word": "Angry", "meaning": "โกรธ", "part_of_speech": "Adjective" },
          { "word": "Excited", "meaning": "ตื่นเต้น", "part_of_speech": "Adjective" },
          { "word": "Bored", "meaning": "เบื่อ", "part_of_speech": "Adjective" },
          { "word": "Tired", "meaning": "เหนื่อย", "part_of_speech": "Adjective" },
          { "word": "Surprised", "meaning": "ประหลาดใจ", "part_of_speech": "Adjective" },
          { "word": "Fearful", "meaning": "กลัว", "part_of_speech": "Adjective" },
          { "word": "Calm", "meaning": "สงบ", "part_of_speech": "Adjective" },
          { "word": "Confused", "meaning": "สับสน", "part_of_speech": "Adjective" },
          { "word": "Nervous", "meaning": "กังวล", "part_of_speech": "Adjective" },
          { "word": "Grateful", "meaning": "รู้สึกขอบคุณ", "part_of_speech": "Adjective" },
          { "word": "Lonely", "meaning": "เหงา", "part_of_speech": "Adjective" },
          { "word": "Proud", "meaning": "ภูมิใจ", "part_of_speech": "Adjective" },
          { "word": "Embarrassed", "meaning": "อับอาย", "part_of_speech": "Adjective" },
          { "word": "Hopeful", "meaning": "มีความหวัง", "part_of_speech": "Adjective" },
          { "word": "Jealous", "meaning": "อิจฉา", "part_of_speech": "Adjective" },
          { "word": "Shocked", "meaning": "ตกใจ", "part_of_speech": "Adjective" },
          { "word": "Content", "meaning": "พอใจ", "part_of_speech": "Adjective" },
          { "word": "Relieved", "meaning": "โล่งใจ", "part_of_speech": "Adjective" }
        ]
      },
      {
        "category_name": "เครื่องใช้ไฟฟ้า (Electronics)",
        "words": [
          { "word": "Phone", "meaning": "โทรศัพท์", "part_of_speech": "Noun" },
          { "word": "Laptop", "meaning": "แล็ปท็อป", "part_of_speech": "Noun" },
          { "word": "Television", "meaning": "โทรทัศน์", "part_of_speech": "Noun" },
          { "word": "Radio", "meaning": "วิทยุ", "part_of_speech": "Noun" },
          { "word": "Camera", "meaning": "กล้อง", "part_of_speech": "Noun" },
          { "word": "Microwave", "meaning": "ไมโครเวฟ", "part_of_speech": "Noun" },
          { "word": "Refrigerator", "meaning": "ตู้เย็น", "part_of_speech": "Noun" },
          { "word": "Fan", "meaning": "พัดลม", "part_of_speech": "Noun" },
          { "word": "Air conditioner", "meaning": "เครื่องปรับอากาศ", "part_of_speech": "Noun" },
          { "word": "Toaster", "meaning": "เครื่องปิ้งขนมปัง", "part_of_speech": "Noun" },
          { "word": "Blender", "meaning": "เครื่องปั่น", "part_of_speech": "Noun" },
          { "word": "Washing machine", "meaning": "เครื่องซักผ้า", "part_of_speech": "Noun" },
          { "word": "Dishwasher", "meaning": "เครื่องล้างจาน", "part_of_speech": "Noun" },
          { "word": "Speaker", "meaning": "ลำโพง", "part_of_speech": "Noun" },
          { "word": "Headphones", "meaning": "หูฟัง", "part_of_speech": "Noun" },
          { "word": "Printer", "meaning": "เครื่องพิมพ์", "part_of_speech": "Noun" },
          { "word": "Projector", "meaning": "โปรเจคเตอร์", "part_of_speech": "Noun" },
          { "word": "Electric kettle", "meaning": "กาน้ำไฟฟ้า", "part_of_speech": "Noun" },
          { "word": "Cordless drill", "meaning": "สว่านไร้สาย", "part_of_speech": "Noun" },
          { "word": "Smartwatch", "meaning": "นาฬิกาอัจฉริยะ", "part_of_speech": "Noun" }
        ]
      },
      {
        "category_name": "กีฬา (Sports)",
        "words": [
          { "word": "Football", "meaning": "ฟุตบอล", "part_of_speech": "Noun" },
          { "word": "Basketball", "meaning": "บาสเกตบอล", "part_of_speech": "Noun" },
          { "word": "Tennis", "meaning": "เทนนิส", "part_of_speech": "Noun" },
          { "word": "Baseball", "meaning": "เบสบอล", "part_of_speech": "Noun" },
          { "word": "Soccer", "meaning": "ฟุตบอล (อีกคำเรียก)", "part_of_speech": "Noun" },
          { "word": "Golf", "meaning": "กอล์ฟ", "part_of_speech": "Noun" },
          { "word": "Swimming", "meaning": "การว่ายน้ำ", "part_of_speech": "Noun" },
          { "word": "Cycling", "meaning": "การปั่นจักรยาน", "part_of_speech": "Noun" },
          { "word": "Boxing", "meaning": "มวย", "part_of_speech": "Noun" },
          { "word": "Badminton", "meaning": "แบดมินตัน", "part_of_speech": "Noun" },
          { "word": "Volleyball", "meaning": "วอลเลย์บอล", "part_of_speech": "Noun" },
          { "word": "Running", "meaning": "การวิ่ง", "part_of_speech": "Noun" },
          { "word": "Skiing", "meaning": "การเล่นสกี", "part_of_speech": "Noun" },
          { "word": "Rugby", "meaning": "รักบี้", "part_of_speech": "Noun" },
          { "word": "Hockey", "meaning": "ฮอกกี้", "part_of_speech": "Noun" },
          { "word": "Wrestling", "meaning": "มวยปล้ำ", "part_of_speech": "Noun" },
          { "word": "Archery", "meaning": "ยิงธนู", "part_of_speech": "Noun" },
          { "word": "Surfing", "meaning": "การโต้คลื่น", "part_of_speech": "Noun" },
          { "word": "Yoga", "meaning": "โยคะ", "part_of_speech": "Noun" },
          { "word": "Cricket", "meaning": "คริกเก็ต", "part_of_speech": "Noun" }
        ]
      },
      {
        "category_name": "การเดินทาง (Travel)",
        "words": [
          { "word": "Flight", "meaning": "เที่ยวบิน", "part_of_speech": "Noun" },
          { "word": "Hotel", "meaning": "โรงแรม", "part_of_speech": "Noun" },
          { "word": "Passport", "meaning": "หนังสือเดินทาง", "part_of_speech": "Noun" },
          { "word": "Luggage", "meaning": "กระเป๋าเดินทาง", "part_of_speech": "Noun" },
          { "word": "Ticket", "meaning": "ตั๋ว", "part_of_speech": "Noun" },
          { "word": "Airport", "meaning": "สนามบิน", "part_of_speech": "Noun" },
          { "word": "Journey", "meaning": "การเดินทาง", "part_of_speech": "Noun" },
          { "word": "Map", "meaning": "แผนที่", "part_of_speech": "Noun" },
          { "word": "Car rental", "meaning": "การเช่ารถ", "part_of_speech": "Noun" },
          { "word": "Travel agency", "meaning": "ตัวแทนท่องเที่ยว", "part_of_speech": "Noun" },
          { "word": "Guidebook", "meaning": "หนังสือนำเที่ยว", "part_of_speech": "Noun" },
          { "word": "Adventure", "meaning": "การผจญภัย", "part_of_speech": "Noun" },
          { "word": "Excursion", "meaning": "การเดินทางสั้น", "part_of_speech": "Noun" },
          { "word": "Cruise", "meaning": "การล่องเรือ", "part_of_speech": "Noun" },
          { "word": "Backpacker", "meaning": "นักเดินทางแบกเป้", "part_of_speech": "Noun" },
          { "word": "Tourist", "meaning": "นักท่องเที่ยว", "part_of_speech": "Noun" },
          { "word": "Destination", "meaning": "จุดหมายปลายทาง", "part_of_speech": "Noun" },
          { "word": "Departure", "meaning": "การออกเดินทาง", "part_of_speech": "Noun" },
          { "word": "Arrival", "meaning": "การมาถึง", "part_of_speech": "Noun" }
        ]
      },
      {
        "category_name": "ธรรมชาติ (Nature)",
        "words": [
          { "word": "Mountain", "meaning": "ภูเขา", "part_of_speech": "Noun" },
          { "word": "River", "meaning": "แม่น้ำ", "part_of_speech": "Noun" },
          { "word": "Forest", "meaning": "ป่า", "part_of_speech": "Noun" },
          { "word": "Desert", "meaning": "ทะเลทราย", "part_of_speech": "Noun" },
          { "word": "Ocean", "meaning": "มหาสมุทร", "part_of_speech": "Noun" },
          { "word": "Lake", "meaning": "ทะเลสาบ", "part_of_speech": "Noun" },
          { "word": "Tree", "meaning": "ต้นไม้", "part_of_speech": "Noun" },
          { "word": "Flower", "meaning": "ดอกไม้", "part_of_speech": "Noun" },
          { "word": "Sun", "meaning": "ดวงอาทิตย์", "part_of_speech": "Noun" },
          { "word": "Cloud", "meaning": "เมฆ", "part_of_speech": "Noun" },
          { "word": "Rain", "meaning": "ฝน", "part_of_speech": "Noun" },
          { "word": "Snow", "meaning": "หิมะ", "part_of_speech": "Noun" },
          { "word": "Wind", "meaning": "ลม", "part_of_speech": "Noun" },
          { "word": "Rock", "meaning": "หิน", "part_of_speech": "Noun" },
          { "word": "Sand", "meaning": "ทราย", "part_of_speech": "Noun" },
          { "word": "Riverbank", "meaning": "ริมแม่น้ำ", "part_of_speech": "Noun" },
          { "word": "Waterfall", "meaning": "น้ำตก", "part_of_speech": "Noun" },
          { "word": "Meadow", "meaning": "ทุ่งหญ้า", "part_of_speech": "Noun" },
          { "word": "Wildlife", "meaning": "สัตว์ป่า", "part_of_speech": "Noun" },
          { "word": "Hill", "meaning": "เนินเขา", "part_of_speech": "Noun" }
        ]
      }
      "words": [
        { "word": "School", "meaning": "โรงเรียน", "part_of_speech": "Noun" },
        { "word": "Hospital", "meaning": "โรงพยาบาล", "part_of_speech": "Noun" },
        { "word": "Restaurant", "meaning": "ร้านอาหาร", "part_of_speech": "Noun" },
        { "word": "Park", "meaning": "สวนสาธารณะ", "part_of_speech": "Noun" },
        { "word": "Library", "meaning": "ห้องสมุด", "part_of_speech": "Noun" },
        { "word": "Airport", "meaning": "สนามบิน", "part_of_speech": "Noun" },
        { "word": "Beach", "meaning": "ชายหาด", "part_of_speech": "Noun" },
        { "word": "Mountain", "meaning": "ภูเขา", "part_of_speech": "Noun" },
        { "word": "City", "meaning": "เมือง", "part_of_speech": "Noun" },
        { "word": "Village", "meaning": "หมู่บ้าน", "part_of_speech": "Noun" },
        { "word": "Bank", "meaning": "ธนาคาร", "part_of_speech": "Noun" },
        { "word": "Hotel", "meaning": "โรงแรม", "part_of_speech": "Noun" },
        { "word": "Store", "meaning": "ร้านค้า", "part_of_speech": "Noun" },
        { "word": "Museum", "meaning": "พิพิธภัณฑ์", "part_of_speech": "Noun" },
        { "word": "Factory", "meaning": "โรงงาน", "part_of_speech": "Noun" },
        { "word": "Office", "meaning": "สำนักงาน", "part_of_speech": "Noun" },
        { "word": "Supermarket", "meaning": "ซูเปอร์มาร์เก็ต", "part_of_speech": "Noun" },
        { "word": "Church", "meaning": "โบสถ์", "part_of_speech": "Noun" },
        { "word": "Temple", "meaning": "วัด", "part_of_speech": "Noun" }
      ]
    },
    {
      "category_name": "อาชีพ (Professions)",
      "words": [
        { "word": "Doctor", "meaning": "หมอ", "part_of_speech": "Noun" },
        { "word": "Teacher", "meaning": "ครู", "part_of_speech": "Noun" },
        { "word": "Engineer", "meaning": "วิศวกร", "part_of_speech": "Noun" },
        { "word": "Nurse", "meaning": "พยาบาล", "part_of_speech": "Noun" },
        { "word": "Chef", "meaning": "เชฟ", "part_of_speech": "Noun" },
        { "word": "Artist", "meaning": "ศิลปิน", "part_of_speech": "Noun" },
        { "word": "Scientist", "meaning": "นักวิทยาศาสตร์", "part_of_speech": "Noun" },
        { "word": "Writer", "meaning": "นักเขียน", "part_of_speech": "Noun" },
        { "word": "Lawyer", "meaning": "ทนายความ", "part_of_speech": "Noun" },
        { "word": "Driver", "meaning": "คนขับรถ", "part_of_speech": "Noun" },
        { "word": "Actor", "meaning": "นักแสดง", "part_of_speech": "Noun" },
        { "word": "Singer", "meaning": "นักร้อง", "part_of_speech": "Noun" },
        { "word": "Dancer", "meaning": "นักเต้น", "part_of_speech": "Noun" },
        { "word": "Photographer", "meaning": "ช่างภาพ", "part_of_speech": "Noun" },
        { "word": "Architect", "meaning": "สถาปนิก", "part_of_speech": "Noun" },
        { "word": "Programmer", "meaning": "โปรแกรมเมอร์", "part_of_speech": "Noun" },
        { "word": "Manager", "meaning": "ผู้จัดการ", "part_of_speech": "Noun" },
        { "word": "Farmer", "meaning": "ชาวนา", "part_of_speech": "Noun" },
        { "word": "Policeman", "meaning": "ตำรวจ", "part_of_speech": "Noun" }
      ]
    },
    {
        "category_name": "เครื่องมือ (Tools)",
        "words": [
          { "word": "Hammer", "meaning": "ค้อน", "part_of_speech": "Noun" },
          { "word": "Screwdriver", "meaning": "ไขควง", "part_of_speech": "Noun" },
          { "word": "Wrench", "meaning": "ประแจ", "part_of_speech": "Noun" },
          { "word": "Pliers", "meaning": "คีม", "part_of_speech": "Noun" },
          { "word": "Drill", "meaning": "สว่าน", "part_of_speech": "Noun" },
          { "word": "Saw", "meaning": "เลื่อย", "part_of_speech": "Noun" },
          { "word": "Tape measure", "meaning": "ไม้วัดระยะ", "part_of_speech": "Noun" },
          { "word": "Level", "meaning": "ระดับ", "part_of_speech": "Noun" },
          { "word": "Chisel", "meaning": "สกัด", "part_of_speech": "Noun" },
          { "word": "File", "meaning": "ไฟล์", "part_of_speech": "Noun" },
          { "word": "Knife", "meaning": "มีด", "part_of_speech": "Noun" },
          { "word": "Shovel", "meaning": "พลั่ว", "part_of_speech": "Noun" },
          { "word": "Pickaxe", "meaning": "ขวานค้อน", "part_of_speech": "Noun" },
          { "word": "Spanner", "meaning": "ประแจเลื่อน", "part_of_speech": "Noun" },
          { "word": "Nail", "meaning": "ตะปู", "part_of_speech": "Noun" },
          { "word": "Screw", "meaning": "สกรู", "part_of_speech": "Noun" },
          { "word": "Bolt", "meaning": "สลักเกลียว", "part_of_speech": "Noun" },
          { "word": "Ladder", "meaning": "บันได", "part_of_speech": "Noun" },
          { "word": "Bucket", "meaning": "ถัง", "part_of_speech": "Noun" },
          { "word": "Torch", "meaning": "ไฟฉาย", "part_of_speech": "Noun" }
        ]
      },
      {
        "category_name": "อารมณ์ (Emotions)",
        "words": [
          { "word": "Happy", "meaning": "มีความสุข", "part_of_speech": "Adjective" },
          { "word": "Sad", "meaning": "เศร้า", "part_of_speech": "Adjective" },
          { "word": "Angry", "meaning": "โกรธ", "part_of_speech": "Adjective" },
          { "word": "Excited", "meaning": "ตื่นเต้น", "part_of_speech": "Adjective" },
          { "word": "Bored", "meaning": "เบื่อ", "part_of_speech": "Adjective" },
          { "word": "Tired", "meaning": "เหนื่อย", "part_of_speech": "Adjective" },
          { "word": "Surprised", "meaning": "ประหลาดใจ", "part_of_speech": "Adjective" },
          { "word": "Fearful", "meaning": "กลัว", "part_of_speech": "Adjective" },
          { "word": "Calm", "meaning": "สงบ", "part_of_speech": "Adjective" },
          { "word": "Confused", "meaning": "สับสน", "part_of_speech": "Adjective" },
          { "word": "Nervous", "meaning": "กังวล", "part_of_speech": "Adjective" },
          { "word": "Grateful", "meaning": "รู้สึกขอบคุณ", "part_of_speech": "Adjective" },
          { "word": "Lonely", "meaning": "เหงา", "part_of_speech": "Adjective" },
          { "word": "Proud", "meaning": "ภูมิใจ", "part_of_speech": "Adjective" },
          { "word": "Embarrassed", "meaning": "อับอาย", "part_of_speech": "Adjective" },
          { "word": "Hopeful", "meaning": "มีความหวัง", "part_of_speech": "Adjective" },
          { "word": "Jealous", "meaning": "อิจฉา", "part_of_speech": "Adjective" },
          { "word": "Shocked", "meaning": "ตกใจ", "part_of_speech": "Adjective" },
          { "word": "Content", "meaning": "พอใจ", "part_of_speech": "Adjective" },
          { "word": "Relieved", "meaning": "โล่งใจ", "part_of_speech": "Adjective" }
        ]
      },
      {
        "category_name": "เครื่องใช้ไฟฟ้า (Electronics)",
        "words": [
          { "word": "Phone", "meaning": "โทรศัพท์", "part_of_speech": "Noun" },
          { "word": "Laptop", "meaning": "แล็ปท็อป", "part_of_speech": "Noun" },
          { "word": "Television", "meaning": "โทรทัศน์", "part_of_speech": "Noun" },
          { "word": "Radio", "meaning": "วิทยุ", "part_of_speech": "Noun" },
          { "word": "Camera", "meaning": "กล้อง", "part_of_speech": "Noun" },
          { "word": "Microwave", "meaning": "ไมโครเวฟ", "part_of_speech": "Noun" },
          { "word": "Refrigerator", "meaning": "ตู้เย็น", "part_of_speech": "Noun" },
          { "word": "Fan", "meaning": "พัดลม", "part_of_speech": "Noun" },
          { "word": "Air conditioner", "meaning": "เครื่องปรับอากาศ", "part_of_speech": "Noun" },
          { "word": "Toaster", "meaning": "เครื่องปิ้งขนมปัง", "part_of_speech": "Noun" },
          { "word": "Blender", "meaning": "เครื่องปั่น", "part_of_speech": "Noun" },
          { "word": "Washing machine", "meaning": "เครื่องซักผ้า", "part_of_speech": "Noun" },
          { "word": "Dishwasher", "meaning": "เครื่องล้างจาน", "part_of_speech": "Noun" },
          { "word": "Speaker", "meaning": "ลำโพง", "part_of_speech": "Noun" },
          { "word": "Headphones", "meaning": "หูฟัง", "part_of_speech": "Noun" },
          { "word": "Printer", "meaning": "เครื่องพิมพ์", "part_of_speech": "Noun" },
          { "word": "Projector", "meaning": "โปรเจคเตอร์", "part_of_speech": "Noun" },
          { "word": "Electric kettle", "meaning": "กาน้ำไฟฟ้า", "part_of_speech": "Noun" },
          { "word": "Cordless drill", "meaning": "สว่านไร้สาย", "part_of_speech": "Noun" },
          { "word": "Smartwatch", "meaning": "นาฬิกาอัจฉริยะ", "part_of_speech": "Noun" }
        ]
      },
      {
        "category_name": "กีฬา (Sports)",
        "words": [
          { "word": "Football", "meaning": "ฟุตบอล", "part_of_speech": "Noun" },
          { "word": "Basketball", "meaning": "บาสเกตบอล", "part_of_speech": "Noun" },
          { "word": "Tennis", "meaning": "เทนนิส", "part_of_speech": "Noun" },
          { "word": "Baseball", "meaning": "เบสบอล", "part_of_speech": "Noun" },
          { "word": "Soccer", "meaning": "ฟุตบอล (อีกคำเรียก)", "part_of_speech": "Noun" },
          { "word": "Golf", "meaning": "กอล์ฟ", "part_of_speech": "Noun" },
          { "word": "Swimming", "meaning": "การว่ายน้ำ", "part_of_speech": "Noun" },
          { "word": "Cycling", "meaning": "การปั่นจักรยาน", "part_of_speech": "Noun" },
          { "word": "Boxing", "meaning": "มวย", "part_of_speech": "Noun" },
          { "word": "Badminton", "meaning": "แบดมินตัน", "part_of_speech": "Noun" },
          { "word": "Volleyball", "meaning": "วอลเลย์บอล", "part_of_speech": "Noun" },
          { "word": "Running", "meaning": "การวิ่ง", "part_of_speech": "Noun" },
          { "word": "Skiing", "meaning": "การเล่นสกี", "part_of_speech": "Noun" },
          { "word": "Rugby", "meaning": "รักบี้", "part_of_speech": "Noun" },
          { "word": "Hockey", "meaning": "ฮอกกี้", "part_of_speech": "Noun" },
          { "word": "Wrestling", "meaning": "มวยปล้ำ", "part_of_speech": "Noun" },
          { "word": "Archery", "meaning": "ยิงธนู", "part_of_speech": "Noun" },
          { "word": "Surfing", "meaning": "การโต้คลื่น", "part_of_speech": "Noun" },
          { "word": "Yoga", "meaning": "โยคะ", "part_of_speech": "Noun" },
          { "word": "Cricket", "meaning": "คริกเก็ต", "part_of_speech": "Noun" }
        ]
      },
      {
        "category_name": "การเดินทาง (Travel)",
        "words": [
          { "word": "Flight", "meaning": "เที่ยวบิน", "part_of_speech": "Noun" },
          { "word": "Hotel", "meaning": "โรงแรม", "part_of_speech": "Noun" },
          { "word": "Passport", "meaning": "หนังสือเดินทาง", "part_of_speech": "Noun" },
          { "word": "Luggage", "meaning": "กระเป๋าเดินทาง", "part_of_speech": "Noun" },
          { "word": "Ticket", "meaning": "ตั๋ว", "part_of_speech": "Noun" },
          { "word": "Airport", "meaning": "สนามบิน", "part_of_speech": "Noun" },
          { "word": "Journey", "meaning": "การเดินทาง", "part_of_speech": "Noun" },
          { "word": "Map", "meaning": "แผนที่", "part_of_speech": "Noun" },
          { "word": "Car rental", "meaning": "การเช่ารถ", "part_of_speech": "Noun" },
          { "word": "Travel agency", "meaning": "ตัวแทนท่องเที่ยว", "part_of_speech": "Noun" },
          { "word": "Guidebook", "meaning": "หนังสือนำเที่ยว", "part_of_speech": "Noun" },
          { "word": "Adventure", "meaning": "การผจญภัย", "part_of_speech": "Noun" },
          { "word": "Excursion", "meaning": "การเดินทางสั้น", "part_of_speech": "Noun" },
          { "word": "Cruise", "meaning": "การล่องเรือ", "part_of_speech": "Noun" },
          { "word": "Backpacker", "meaning": "นักเดินทางแบกเป้", "part_of_speech": "Noun" },
          { "word": "Tourist", "meaning": "นักท่องเที่ยว", "part_of_speech": "Noun" },
          { "word": "Destination", "meaning": "จุดหมายปลายทาง", "part_of_speech": "Noun" },
          { "word": "Departure", "meaning": "การออกเดินทาง", "part_of_speech": "Noun" },
          { "word": "Arrival", "meaning": "การมาถึง", "part_of_speech": "Noun" }
        ]
      },
      {
        "category_name": "ธรรมชาติ (Nature)",
        "words": [
          { "word": "Mountain", "meaning": "ภูเขา", "part_of_speech": "Noun" },
          { "word": "River", "meaning": "แม่น้ำ", "part_of_speech": "Noun" },
          { "word": "Forest", "meaning": "ป่า", "part_of_speech": "Noun" },
          { "word": "Desert", "meaning": "ทะเลทราย", "part_of_speech": "Noun" },
          { "word": "Ocean", "meaning": "มหาสมุทร", "part_of_speech": "Noun" },
          { "word": "Lake", "meaning": "ทะเลสาบ", "part_of_speech": "Noun" },
          { "word": "Tree", "meaning": "ต้นไม้", "part_of_speech": "Noun" },
          { "word": "Flower", "meaning": "ดอกไม้", "part_of_speech": "Noun" },
          { "word": "Sun", "meaning": "ดวงอาทิตย์", "part_of_speech": "Noun" },
          { "word": "Cloud", "meaning": "เมฆ", "part_of_speech": "Noun" },
          { "word": "Rain", "meaning": "ฝน", "part_of_speech": "Noun" },
          { "word": "Snow", "meaning": "หิมะ", "part_of_speech": "Noun" },
          { "word": "Wind", "meaning": "ลม", "part_of_speech": "Noun" },
          { "word": "Rock", "meaning": "หิน", "part_of_speech": "Noun" },
          { "word": "Sand", "meaning": "ทราย", "part_of_speech": "Noun" },
          { "word": "Riverbank", "meaning": "ริมแม่น้ำ", "part_of_speech": "Noun" },
          { "word": "Waterfall", "meaning": "น้ำตก", "part_of_speech": "Noun" },
          { "word": "Meadow", "meaning": "ทุ่งหญ้า", "part_of_speech": "Noun" },
          { "word": "Wildlife", "meaning": "สัตว์ป่า", "part_of_speech": "Noun" },
          { "word": "Hill", "meaning": "เนินเขา", "part_of_speech": "Noun" }
        ]
      }
  ]
  
  

// ฟังก์ชันเพิ่มหมวดหมู่เริ่มต้นใน Firestore
// Environment Guard for Maintainer Seed Utility
function checkEnvironmentGuard() {
  const isEmulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
  const isDev = process.env.NODE_ENV === 'development' || process.env.ALLOW_SEED === 'true';
  if (!isEmulator && !isDev) {
    throw new Error(
      'Environment Guard: Seed script blocked in non-development/non-emulator environment.'
    );
  }
}

const addDefaultCategories = async (systemUid = 'system_seed') => {
  checkEnvironmentGuard();

  for (const category of defaultCategories) {
    const categoryRef = db.collection('categories').doc(category.category_name);
    const categoryData = {
      category_name: category.category_name,
      created_at: FieldValue.serverTimestamp(),
      uid: systemUid,
    };

    await categoryRef.set(categoryData);

    const wordsRef = categoryRef.collection('words');
    for (const w of category.words) {
      const wordDocRef = wordsRef.doc(w.word);
      await wordDocRef.set({
        word: w.word,
        meaning: w.meaning,
        part_of_speech: w.part_of_speech,
        user_id: systemUid,
        is_global: true,
        created_at: FieldValue.serverTimestamp(),
      });
    }

    console.log(`Added category: ${category.category_name}`);
  }
};

module.exports = { addDefaultCategories, checkEnvironmentGuard };

// เรียกฟังก์ชันเพิ่มหมวดหมู่เริ่มต้นเฉพาะเมื่อรันเป็น CLI โดยตรง
if (require.main === module) {
  addDefaultCategories().catch((error) => {
    console.error(
      'Failed to add default categories:',
      error && error.message ? error.message : 'unknown error',
    );
    process.exitCode = 1;
  });
}
