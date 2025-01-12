import 'package:flutter/material.dart';
import 'package:vocab_learning_app/screens/vocab_list_screen.dart';
import '../models/category_model.dart';
import '../services/category_service.dart';

class CategoriesPage extends StatelessWidget {
  final CategoryService _categoryService = CategoryService();

  CategoriesPage({super.key});

  // Function to delete a category with confirmation dialog
  void _deleteCategory(BuildContext context, String categoryId, String categoryName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text('Are you sure you want to delete the category "$categoryName"?'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text('Delete'),
            onPressed: () async {
              await _categoryService.deleteCategory(categoryId);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  // Function to show the add category dialog
  void _showAddCategoryDialog(BuildContext context) {
    TextEditingController addController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Category'),
        content: TextField(
          controller: addController,
          decoration: const InputDecoration(labelText: 'Category Name'),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text('Add'),
            onPressed: () async {
              final categoryName = addController.text.trim();
              if (categoryName.isNotEmpty) {
                await _categoryService.addCategory(categoryName);
              }
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
      ),
      body: StreamBuilder<List<Category>>(
        stream: _categoryService.getCategoriesStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Error loading categories.'));
          }
          final categories = snapshot.data ?? [];
          if (categories.isEmpty) {
            return const Center(child: Text('No categories found.'));
          }
          return ListView.builder(
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              return GestureDetector(
                onLongPress: () => _deleteCategory(context, category.id!, category.name),
                onTap: () {
                  Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => VocabListScreen(
      categoryId: category.id!,
      categoryName: category.name, // ส่ง categoryName ไป VocabListScreen
    ),
  ),
);

                },
                child: Card(
                  margin: const EdgeInsets.all(8),
                  child: ListTile(
                    title: Text(category.name),
                    trailing: const Icon(Icons.arrow_forward),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddCategoryDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}
