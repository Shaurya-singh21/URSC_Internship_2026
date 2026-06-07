#include <algorithm>
#include <iostream>
#include <cmath>
#include <cstdio>
#include <vector>
#include <random>
#include <cstdlib>
#include "star_catalog.h"
using namespace std;

struct Star{
    float x;
    float y;
    float brightness;
};

double get_catalog_angle(int i, int j) {
    double dot = (star_catalog[i].x * star_catalog[j].x) +
                 (star_catalog[i].y * star_catalog[j].y) +
                 (star_catalog[i].z * star_catalog[j].z);
    
    if (dot > 1.0)  dot = 1.0;
    if (dot < -1.0) dot = -1.0;
    return acos(dot); // Angle in Radians
}

int random_pixels(int rows,int cols) {
    int m = rows+2, n = cols+2; //size
    int pixels[m][n];
    for(int i=0;i<m;i++){
        for(int j=0;j<n;j++){
            if((i == 0 || i == m-1) || (j == 0 || j == n-1)) pixels[i][j] = 0;
            else pixels[i][j] = rand() % 256;
            // cout << pixels[i][j]<<endl;
        }
    }
    return pixels[m][n];

}

int main()
{   
    //generate random pixel data for testing
    int rows = 64, cols = 64;
    int pixels[rows+2][cols+2];
    pixels[rows+2][cols+2] = random_pixels(rows, cols);
    
    //now filter noise and then extract star coordinates and brightness from pixel data
    int star_cnt = 0;
    vector<Star> coord;

    int star_start = 0;
    int threshold = 150;
    int acc = 0;
    int m_x= 0;
    int m_y = 0;
    int ct = 0;
    for(int i=1;i<rows+1;i++){
        for(int j=1;j<cols+1;j++){
            if(pixels[i][j] >= threshold){
                int left = pixels[i][j-1];
                int top_left = pixels[i-1][j-1];
                int top = pixels[i-1][j];
                int top_right = pixels[i-1][j+1];
                if(left < threshold && top_left < threshold && top < threshold && top_right < threshold){
                    star_start = 1;
                    acc = 0;
                    m_x = 0;
                    m_y = 0;
                }
                acc += pixels[i][j];
                m_x += (j)*pixels[i][j];
                m_y += (i)*pixels[i][j];
                ct++;
            }else{
                if(star_start){
                    if(ct >= 1 && acc > 0){
                        Star new_star;
                        new_star.x = float(m_x) / acc;
                        new_star.y = float(m_y) / acc;
                        new_star.brightness = float(acc);
                        coord.push_back(new_star);
                        star_cnt++;
                    }
                    star_start = 0;
                }
            }
        }
    }

    //now find top 3 brightest stars and sort them in descending order of brightness
    for(int i=0;i<star_cnt;i++){
        for(int j=i+1;j<star_cnt;j++){
            if(coord[i].brightness < coord[j].brightness){
                swap(coord[i],coord[j]);
            }
        }
    }

    // for(int i=0;i<star_cnt;i++){
    //     cout << coord[i].x <<" "<<coord[i].y<<" "<<coord[i].brightness<<endl;
    // }

    //now adjust for the zoom and other camera parameters to get unit vectors for the 3 brightest stars
    int focal_length = 700;
    int cx = 32;
    int cy = 32;
    double unit_vec[3][3];
    int idx = 0;
    for(int i=0;i<3;i++){
        double X = (coord[i].x - cx);
        double Y = (coord[i].y - cy);
        double Z = focal_length;
        double norm = sqrt(X*X + Y*Y + Z*Z);
        unit_vec[idx][0] = X/norm;
        unit_vec[idx][1] = Y/norm;
        unit_vec[idx][2] = Z/norm;
        idx++;
    }

    //we have unit vector now find the angles between them 
    vector<double> obs_angles;
    for(int i=0;i<3;i++){
        for(int j=i+1;j<3;j++){
            double dot_product = unit_vec[i][0]*unit_vec[j][0] + unit_vec[i][1]*unit_vec[j][1] + unit_vec[i][2]*unit_vec[j][2];
            if (dot_product > 1.0)  dot_product = 1.0;
            if (dot_product < -1.0) dot_product = -1.0;
            obs_angles.push_back(acos(dot_product));    
        }
    }
    double obs_angle_12 = obs_angles[0];
    double obs_angle_23 = obs_angles[1];
    double obs_angle_31 = obs_angles[2];   

    //now compare them to catalog angles and find the best match for the 3 brightest stars in the image
    float tol = 0.07;
    bool lock_secured = false;


    for (int i = 0; i < CATALOG_SIZE; i++) {
        for (int j = i + 1; j < CATALOG_SIZE; j++) {
            double cat_angle_12 = get_catalog_angle(i, j);
            if (abs(cat_angle_12 - obs_angle_12) > tol) continue; 
            //if 2 are within tolerance then only check for the 3rd leg otherwise skip to next pair 
            for (int k = j + 1; k < CATALOG_SIZE; k++) {
                double cat_angle_23 = get_catalog_angle(j, k);
                if (abs(cat_angle_23 - obs_angle_23) > tol) continue;
                double cat_angle_31 = get_catalog_angle(k, i);
                if (abs(cat_angle_31 - obs_angle_31) > tol) continue;
        
                //pattern found
                cout << "========================================================\n";
                cout << " CELESTIAL IDENTITY ENGINE RESOLVED MATCH FOUND\n";
                cout << "========================================================\n";
                cout << "Observed Star 1 aligns directly with Catalog Index Slot: " << i << "\n";
                cout << "Observed Star 2 aligns directly with Catalog Index Slot: " << j << "\n";
                cout << "Observed Star 3 aligns directly with Catalog Index Slot: " << k << "\n";
                
                lock_secured = true;
                break; 
            }
            if (lock_secured) break;
        }
        if (lock_secured) break;
    }

    if (!lock_secured) {
        cout << "Navigation Lookup Alert: No unique catalog geometry correlates to current camera image." << endl;
    }
    return 0;

};
